use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use anyhow::{Context, Result, anyhow, bail};
#[cfg(all(target_os = "linux", feature = "flatpak"))]
use cpp::cpp;
use log::{error, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::{QVariantList, QVariantMap};

cpp::cpp! {{
    #ifdef IDESCRIPTOR_FLATPAK
    #include <QDBusConnection>
    #include <QDBusConnectionInterface>
    #include <QDBusReply>
    #include <QDebug>

    static bool idescriptor_is_avahi_available()
    {
        QDBusConnection bus = QDBusConnection::systemBus();

        if (!bus.isConnected()) {
            qWarning() << "Cannot connect to the D-Bus system bus";
            return false;
        }

        QDBusConnectionInterface *interface = bus.interface();
        QDBusReply<bool> reply =
            interface->isServiceRegistered(QStringLiteral("org.freedesktop.Avahi"));

        if (!reply.isValid()) {
            qWarning() << "Failed to query Avahi service registration:"
                       << reply.error().message();
            return false;
        }

        return reply.value();
    }
    #else
    // have to define this because
    // cpp_build scans cpp! blocks even when the Rust call is feature-gated.
    static bool idescriptor_is_avahi_available()
    {
        return false;
    }
    #endif
}}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Availability {
    Available,
    AvailableButNotRunning,
    Unavailable,
    UnableToCheck,
}

#[derive(Clone, Debug)]
struct DependencyStatus {
    id: &'static str,
    name: &'static str,
    description: &'static str,
    optional: bool,
    availability: Availability,
    action_text: &'static str,
}

#[derive(QObject, Default, QtThreading)]
pub struct Diagnose {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),
    check: qt_method!(fn(&mut self)),
    install: qt_method!(fn(&mut self, dependency_id: QString)),
    clear_notice: qt_method!(fn(&mut self)),
}

impl Diagnose {
    pub fn new_with_state() -> Self {
        let mut def = Self::default();
        def.state = build_state(Vec::new(), true, QString::default(), false);
        def
    }

    fn check(&mut self) {
        self.state = build_state(Vec::new(), true, QString::default(), false);
        self.state_changed();

        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            let result = check_dependencies().await;
            q_thread.queue(move |t| match result {
                Ok(items) => {
                    t.state = build_state(items, false, QString::default(), false);
                    t.state_changed();
                }
                Err(err) => {
                    error!("diagnose check failed: {err:#}");
                    t.state = build_error_state(format!("{err:#}"));
                    t.state_changed();
                }
            });
        });
    }

    fn install(&mut self, dependency_id: QString) {
        let dependency_id = dependency_id.to_string();
        if dependency_id.is_empty() {
            return;
        }

        self.set_installing(&dependency_id);
        let q_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let result = install_dependency(&dependency_id).await;
            let check_result = check_dependencies().await;

            q_thread.queue(move |t| {
                let notice = match result {
                    Ok(message) => QString::from(message),
                    Err(err) => {
                        error!("dependency install action failed for {dependency_id}: {err:#}");
                        QString::from(format!("{err:#}"))
                    }
                };

                t.state = match check_result {
                    Ok(items) => build_state(items, false, notice, false),
                    Err(err) => build_error_state(format!("{err:#}")),
                };
                t.state_changed();
            });
        });
    }

    fn clear_notice(&mut self) {
        let mut state = self.state.clone();
        qvariantmap_insert!(state, "notice", QString::default());
        self.state = state;
        self.state_changed();
    }

    fn set_installing(&mut self, dependency_id: &str) {
        let mut state = self.state.clone();
        qvariantmap_insert!(state, "checking", false);
        qvariantmap_insert!(state, "installingId", QString::from(dependency_id));
        qvariantmap_insert!(state, "notice", QString::default());
        self.state = state;
        self.state_changed();
    }
}

fn build_error_state(error: String) -> QVariantMap {
    let mut state = QVariantMap::default();
    qvariantmap_insert!(state, "checking", false);
    qvariantmap_insert!(state, "error", QString::from(error));
    qvariantmap_insert!(
        state,
        "summary",
        QString::from("Unable to check system dependencies")
    );
    qvariantmap_insert!(state, "summaryKind", QString::from("error"));
    qvariantmap_insert!(state, "shouldExpand", true);
    qvariantmap_insert!(state, "requiredMissing", true);
    qvariantmap_insert!(state, "notice", QString::default());
    qvariantmap_insert!(state, "installingId", QString::default());
    qvariantmap_insert!(state, "items", QVariantList::default());
    state
}

fn build_state(
    items: Vec<DependencyStatus>,
    checking: bool,
    notice: QString,
    required_missing_override: bool,
) -> QVariantMap {
    let total = items.iter().filter(|item| !item.optional).count();
    let installed = items
        .iter()
        .filter(|item| !item.optional && item.availability == Availability::Available)
        .count();
    let required_missing = required_missing_override
        || items.iter().any(|item| {
            !item.optional
                && matches!(
                    item.availability,
                    Availability::Unavailable
                        | Availability::UnableToCheck
                        | Availability::AvailableButNotRunning
                )
        });
    let optional_available = items
        .iter()
        .filter(|item| item.optional && item.availability != Availability::Available)
        .count();

    let summary = if checking {
        "Checking system dependencies...".to_string()
    } else if required_missing {
        format!("Missing required dependencies ({installed}/{total} installed)")
    } else if optional_available > 0 {
        let noun = if optional_available == 1 {
            "capability"
        } else {
            "capabilities"
        };
        format!("{optional_available} optional {noun} available")
    } else if total == 0 {
        "No system dependencies are required on this platform".to_string()
    } else {
        "All required dependencies are installed".to_string()
    };

    let summary_kind = if checking {
        "loading"
    } else if required_missing {
        "error"
    } else if optional_available > 0 {
        "warning"
    } else {
        "ok"
    };

    let mut state = QVariantMap::default();
    qvariantmap_insert!(state, "checking", checking);
    qvariantmap_insert!(state, "error", QString::default());
    qvariantmap_insert!(state, "summary", QString::from(summary));
    qvariantmap_insert!(state, "summaryKind", QString::from(summary_kind));
    qvariantmap_insert!(state, "shouldExpand", required_missing);
    qvariantmap_insert!(state, "requiredMissing", required_missing);
    qvariantmap_insert!(state, "notice", notice);
    qvariantmap_insert!(state, "installingId", QString::default());
    qvariantmap_insert!(state, "items", items_to_variant_list(items));
    state
}

fn items_to_variant_list(items: Vec<DependencyStatus>) -> QVariantList {
    let mut list = QVariantList::default();
    for item in items {
        let mut map = QVariantMap::default();
        qvariantmap_insert!(map, "id", QString::from(item.id));
        qvariantmap_insert!(map, "name", QString::from(item.name));
        qvariantmap_insert!(map, "description", QString::from(item.description));
        qvariantmap_insert!(map, "optional", item.optional);
        qvariantmap_insert!(map, "availability", availability_code(item.availability));
        qvariantmap_insert!(
            map,
            "statusText",
            QString::from(status_text(item.availability))
        );
        qvariantmap_insert!(
            map,
            "statusKind",
            QString::from(status_kind(item.availability))
        );
        qvariantmap_insert!(map, "actionText", QString::from(item.action_text));
        let action_visible = item.availability != Availability::Available
            && !(cfg!(all(target_os = "linux", feature = "flatpak")) && item.id == "avahi");
        qvariantmap_insert!(map, "actionVisible", action_visible);
        list.push(QVariant::from(map));
    }
    list
}

fn availability_code(availability: Availability) -> i32 {
    match availability {
        Availability::Available => 0,
        Availability::AvailableButNotRunning => 1,
        Availability::Unavailable => 2,
        Availability::UnableToCheck => 3,
    }
}

fn status_text(availability: Availability) -> &'static str {
    match availability {
        Availability::Available => "Installed",
        Availability::AvailableButNotRunning => "Installed, not running",
        Availability::Unavailable => "Missing",
        Availability::UnableToCheck => "Unable to check",
    }
}

fn status_kind(availability: Availability) -> &'static str {
    match availability {
        Availability::Available => "ok",
        Availability::AvailableButNotRunning => "warning",
        Availability::Unavailable | Availability::UnableToCheck => "error",
    }
}

async fn check_dependencies() -> Result<Vec<DependencyStatus>> {
    #[cfg(target_os = "windows")]
    {
        return check_windows_dependencies().await;
    }

    #[cfg(target_os = "linux")]
    {
        return check_linux_dependencies().await;
    }

    #[allow(unreachable_code)]
    Ok(Vec::new())
}

async fn install_dependency(dependency_id: &str) -> Result<String> {
    #[cfg(target_os = "windows")]
    {
        return install_windows_dependency(dependency_id).await;
    }

    #[cfg(target_os = "linux")]
    {
        return install_linux_dependency(dependency_id).await;
    }

    #[allow(unreachable_code)]
    Err(anyhow!("No install action is available on this platform"))
}

#[cfg(target_os = "linux")]
async fn check_linux_dependencies() -> Result<Vec<DependencyStatus>> {
    #[cfg(feature = "flatpak")]
    let avahi = match tokio::task::spawn_blocking(|| {
        cpp!(unsafe [] -> bool as "bool" {
            return idescriptor_is_avahi_available();
        })
    })
    .await
    {
        Ok(true) => Availability::Available,
        Ok(false) => Availability::AvailableButNotRunning,
        Err(err) => {
            warn!("failed to check Avahi over D-Bus: {err}");
            Availability::UnableToCheck
        }
    };

    #[cfg(not(feature = "flatpak"))]
    let avahi = linux_service_status("avahi-daemon.service", &["avahi-browse", "avahi-daemon"])
        .await
        .unwrap_or_else(|err| {
            warn!("failed to check avahi: {err:#}");
            Availability::UnableToCheck
        });

    #[cfg(not(feature = "flatpak"))]
    let udev_rules = check_udev_rules_installed().await.unwrap_or_else(|err| {
        warn!("failed to check udev rules: {err:#}");
        Availability::UnableToCheck
    });

    #[allow(unused_mut)]
    let mut dependencies = vec![DependencyStatus {
        id: "avahi",
        name: "Avahi Daemon",
        description: "Required for AirPlay and wireless device discovery.",
        optional: false,
        availability: avahi,
        action_text: if avahi == Availability::AvailableButNotRunning {
            "Start"
        } else {
            "Install"
        },
    }];

    #[cfg(not(feature = "flatpak"))]
    dependencies.push(DependencyStatus {
        id: "udev_rules",
        name: "UDEV rules",
        description: "Optional USB permissions for devices in recovery mode.",
        optional: true,
        availability: udev_rules,
        action_text: "View Instructions",
    });

    Ok(dependencies)
}

#[cfg(all(target_os = "linux", not(feature = "flatpak")))]
async fn check_udev_rules_installed() -> Result<Availability> {
    use std::time::Duration;

    let content = match tokio::fs::read_to_string("/etc/udev/rules.d/99-idevice.rules").await {
        Ok(content) => content,
        Err(err) => {
            log::debug!("unable to read idevice udev rules: {err}");
            return Ok(Availability::UnableToCheck);
        }
    };

    let has_usb_subsystem = content.contains("SUBSYSTEM==\"usb\"");
    let has_apple_vendor = content.contains("ATTR{idVendor}==\"05ac\"");
    let has_mode = content.contains("MODE=\"0666\"");

    if !has_usb_subsystem || !has_apple_vendor || !has_mode {
        return Ok(Availability::UnableToCheck);
    }

    let groups_output = match tokio::time::timeout(
        Duration::from_secs(3),
        tokio::process::Command::new("groups").output(),
    )
    .await
    {
        Ok(Ok(output)) if output.status.success() => output,
        Ok(Ok(output)) => {
            log::debug!("groups command failed with status {}", output.status);
            return Ok(Availability::UnableToCheck);
        }
        Ok(Err(err)) => {
            log::debug!("failed to run groups command: {err}");
            return Ok(Availability::UnableToCheck);
        }
        Err(_) => {
            log::debug!("groups command timed out");
            return Ok(Availability::UnableToCheck);
        }
    };

    let groups = String::from_utf8_lossy(&groups_output.stdout);
    if groups.split_whitespace().any(|group| group == "idevice") {
        Ok(Availability::Available)
    } else {
        Ok(Availability::UnableToCheck)
    }
}

#[cfg(all(target_os = "linux", not(feature = "flatpak")))]
async fn linux_service_status(service: &str, binaries: &[&str]) -> Result<Availability> {
    if command_success("systemctl", &["is-active", "--quiet", service]).await {
        return Ok(Availability::Available);
    }

    if binaries.iter().any(|binary| executable_in_path(binary)) {
        return Ok(Availability::AvailableButNotRunning);
    }

    Ok(Availability::Unavailable)
}

#[cfg(target_os = "linux")]
async fn install_linux_dependency(dependency_id: &str) -> Result<String> {
    match dependency_id {
        "udev_rules" => Ok("Install the iDescriptor udev rules at /etc/udev/rules.d/99-idevice.rules, reload udev, and add your user to the idevice group. Then sign out and back in before refreshing diagnostics.".to_string()),
        "avahi" => {
            if cfg!(feature = "flatpak") {
                bail!("Starting host services is not available in the Flatpak build");
            }

            if executable_in_path("systemctl") && executable_in_path("pkexec") {
                tokio::process::Command::new("pkexec")
                    .args(["systemctl", "enable", "--now", "avahi-daemon.service"])
                    .status()
                    .await
                    .context("Failed to start Avahi with pkexec")?;
                Ok("Avahi start command finished. Refresh the check if the status did not update automatically.".to_string())
            } else {
                Ok("Install and start the avahi daemon with your system package manager.".to_string())
            }
        }
        _ => bail!("Unknown dependency: {dependency_id}"),
    }
}

#[cfg(target_os = "windows")]
async fn check_windows_dependencies() -> Result<Vec<DependencyStatus>> {
    let bonjour = windows_service_status("Bonjour Service").await;
    let apple_mobile = windows_service_status("Apple Mobile Device Service").await;
    let winfsp = windows_service_status("WinFsp.Launcher").await;

    Ok(vec![
        DependencyStatus {
            id: "bonjour",
            name: "Bonjour Service",
            description: "Required for AirPlay, wireless devices and network service discovery.",
            optional: false,
            availability: bonjour,
            action_text: if bonjour == Availability::AvailableButNotRunning {
                "Start"
            } else {
                "Install"
            },
        },
        DependencyStatus {
            id: "apple_mobile_device_support",
            name: "Apple Mobile Device Support",
            description: "Required for iOS device communication.",
            optional: false,
            availability: apple_mobile,
            action_text: if apple_mobile == Availability::AvailableButNotRunning {
                "Start"
            } else {
                "Install"
            },
        },
        DependencyStatus {
            id: "winfsp",
            name: "WinFsp",
            description: "Optional. Required for mounting the device as a drive.",
            optional: true,
            availability: winfsp,
            action_text: if winfsp == Availability::AvailableButNotRunning {
                "Start"
            } else {
                "Install"
            },
        },
    ])
}

#[cfg(target_os = "windows")]
async fn windows_service_status(service: &str) -> Availability {
    match tokio::process::Command::new("sc")
        .args(["query", service])
        .output()
        .await
    {
        Ok(output) if output.status.success() => {
            let text = String::from_utf8_lossy(&output.stdout);
            if text.contains("RUNNING") {
                Availability::Available
            } else {
                Availability::AvailableButNotRunning
            }
        }
        Ok(output) => {
            log::debug!(
                "service check failed for {service}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            Availability::Unavailable
        }
        Err(err) => {
            warn!("unable to query service {service}: {err}");
            Availability::UnableToCheck
        }
    }
}

#[cfg(target_os = "windows")]
async fn install_windows_dependency(dependency_id: &str) -> Result<String> {
    match dependency_id {
        "bonjour" => {
            if windows_service_status("Bonjour Service").await
                == Availability::AvailableButNotRunning
            {
                start_windows_service("Bonjour Service").await?;
                Ok("Bonjour Service start command was sent.".to_string())
            } else {
                install_bonjour().await
            }
        }
        "apple_mobile_device_support" => {
            if windows_service_status("Apple Mobile Device Service").await
                == Availability::AvailableButNotRunning
            {
                start_windows_service("Apple Mobile Device Service").await?;
                Ok("Apple Mobile Device Service start command was sent.".to_string())
            } else {
                run_bundled_elevated_script("install-apple-drivers.ps1")
                    .await
                    .map(|_| "Apple Mobile Device Support installer was started.".to_string())
            }
        }
        "winfsp" => {
            if windows_service_status("WinFsp.Launcher").await
                == Availability::AvailableButNotRunning
            {
                start_windows_service("WinFsp.Launcher").await?;
                Ok("WinFsp service start command was sent.".to_string())
            } else {
                run_bundled_elevated_script("install-win-fsp.silent.bat")
                    .await
                    .map(|_| "WinFsp installer was started.".to_string())
            }
        }
        _ => bail!("Unknown dependency: {dependency_id}"),
    }
}

#[cfg(target_os = "windows")]
async fn install_bonjour() -> Result<String> {
    use md5::{Digest, Md5};

    const BONJOUR_URL: &str =
        "https://github.com/tempx-x/bonjour-sdk/raw/refs/heads/main/bonjoursdksetup.exe";
    const BONJOUR_MD5: &str = "4ff2aae8205aec31b06743782cfcadce";

    log::info!("downloading Bonjour SDK installer");
    let bytes = reqwest::get(BONJOUR_URL)
        .await
        .context("Failed to start Bonjour download")?
        .bytes()
        .await
        .context("Failed to read Bonjour download")?;

    let digest = format!("{:x}", Md5::digest(&bytes));
    if digest != BONJOUR_MD5 {
        bail!("Bonjour installer checksum mismatch");
    }

    let temp_dir =
        std::env::temp_dir().join(format!("idescriptor-bonjour-{}", uuid::Uuid::new_v4()));
    tokio::fs::create_dir_all(&temp_dir)
        .await
        .with_context(|| format!("Failed to create {}", temp_dir.display()))?;

    let exe_path = temp_dir.join("bonjoursdksetup.exe");
    let msi_path = temp_dir.join("Bonjour64.msi");
    tokio::fs::write(&exe_path, bytes)
        .await
        .with_context(|| format!("Failed to write {}", exe_path.display()))?;

    let entries =
        compress_tools::tokio_support::list_archive_files(tokio::fs::File::open(&exe_path).await?)
            .await
            .context("Failed to inspect Bonjour installer archive")?;
    let msi_entry = entries
        .into_iter()
        .find(|entry| entry.to_ascii_lowercase().ends_with("bonjour64.msi"))
        .ok_or_else(|| anyhow!("Bonjour64.msi was not found inside the installer"))?;

    let source = tokio::fs::File::open(&exe_path).await?;
    let target = tokio::fs::File::create(&msi_path).await?;
    compress_tools::tokio_support::uncompress_archive_file(source, target, &msi_entry)
        .await
        .context("Failed to extract Bonjour64.msi")?;

    run_powershell_elevated(&format!(
        "Start-Process -FilePath '{}' -Verb RunAs",
        powershell_quote_path(&msi_path)
    ))
    .await?;

    Ok("Bonjour installer was started. Refresh the check after installation finishes.".to_string())
}

#[cfg(target_os = "windows")]
async fn run_bundled_elevated_script(script_name: &str) -> Result<()> {
    let exe_dir = std::env::current_exe()
        .context("Failed to locate current executable")?
        .parent()
        .ok_or_else(|| anyhow!("Failed to locate application directory"))?
        .to_path_buf();
    let script_path = exe_dir.join(script_name);
    if !script_path.exists() {
        bail!("Installer script was not found: {}", script_path.display());
    }

    let command = if script_name.ends_with(".ps1") {
        format!(
            "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"{}\"' -Verb RunAs",
            powershell_quote_path(&script_path)
        )
    } else {
        format!(
            "Start-Process -FilePath '{}' -Verb RunAs",
            powershell_quote_path(&script_path)
        )
    };

    run_powershell_elevated(&command).await
}

#[cfg(target_os = "windows")]
async fn run_powershell_elevated(command: &str) -> Result<()> {
    let status = tokio::process::Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            command,
        ])
        .status()
        .await
        .context("Failed to launch elevated PowerShell command")?;
    if status.success() {
        Ok(())
    } else {
        bail!("Elevated command failed with status {status}");
    }
}

#[cfg(target_os = "windows")]
async fn start_windows_service(service: &str) -> Result<()> {
    let service = service.replace('\'', "''");
    run_powershell_elevated(&format!(
        "Set-Service -Name '{service}' -StartupType Automatic; Start-Service -Name '{service}'"
    ))
    .await
}

#[cfg(target_os = "windows")]
fn powershell_quote_path(path: &std::path::Path) -> String {
    path.to_string_lossy().replace('\'', "''")
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
async fn command_success(program: &str, args: &[&str]) -> bool {
    tokio::process::Command::new(program)
        .args(args)
        .status()
        .await
        .map(|status| status.success())
        .unwrap_or(false)
}

#[cfg(target_os = "linux")]
fn executable_in_path(binary: &str) -> bool {
    let Some(paths) = std::env::var_os("PATH") else {
        return false;
    };

    std::env::split_paths(&paths).any(|dir| {
        let candidate = dir.join(binary);
        candidate.is_file()
    })
}
