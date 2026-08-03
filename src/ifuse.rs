use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use ::log::{error, info};
#[cfg(all(target_os = "linux", feature = "flatpak"))]
use cpp::cpp;
use ifuse::{IfuseBuilder, MountHandle};
use macros::QtThreading;
use once_cell::sync::Lazy;
use qmetaobject::prelude::*;
use qttypes::QVariantMap;
use std::sync::Mutex;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
};

#[cfg(target_os = "linux")]
use tokio::process::Command;

#[cfg(all(target_os = "linux", feature = "flatpak"))]
cpp! {{
    #include <QStandardPaths>
}}

#[cfg(target_os = "linux")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ExternalMountLocation {
    #[cfg(not(feature = "flatpak"))]
    Local,
    #[cfg(feature = "flatpak")]
    Host,
}

#[derive(Clone)]
enum RegistryMount {
    Pending {
        udid: String,
    },
    Embedded {
        udid: String,
        handle: MountHandle,
    },
    #[cfg(target_os = "linux")]
    External {
        udid: String,
        mount_path: String,
        location: ExternalMountLocation,
    },
}

#[cfg(target_os = "linux")]
enum LinuxMount {
    Embedded(MountHandle),
    External(ExternalMountLocation),
}

static MOUNTS: Lazy<Mutex<HashMap<String, RegistryMount>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct IFuse {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY stateChanged),
    stateChanged: qt_signal!(),
    deviceStateChanged: qt_signal!(udid: QString),
    device_states: HashMap<String, QVariantMap>,
    state_for_device: qt_method!(fn(&self, udid: QString) -> QVariantMap),
    is_flatpak_build: qt_method!(fn(&self) -> bool),
    mount_root_path: qt_method!(fn(&self) -> QString),
    is_mount_path_supported: qt_method!(fn(&self, mount_path: QString) -> bool),
    default_mount_path: qt_method!(fn(&self, product_type: QString) -> QString),
    mount: qt_method!(fn(&mut self, udid: QString, mount_path: QString)),
    unmount: qt_method!(fn(&mut self, mount_path: QString)),
    unmount_device: qt_method!(fn(&mut self, udid: QString)),
    unmount_device_path: qt_method!(fn(&mut self, udid: QString, mount_path: QString)),
}

impl IFuse {
    pub fn new_with_state() -> Self {
        let state = default_state();
        Self {
            state,
            ..Default::default()
        }
    }

    fn state_for_device(&self, udid: QString) -> QVariantMap {
        self.device_states
            .get(&udid.to_string())
            .cloned()
            .unwrap_or_else(default_state)
    }

    fn is_flatpak_build(&self) -> bool {
        cfg!(all(target_os = "linux", feature = "flatpak"))
    }

    fn mount_root_path(&self) -> QString {
        QString::from(mount_root_path().to_string_lossy().to_string())
    }

    fn is_mount_path_supported(&self, mount_path: QString) -> bool {
        is_mount_path_supported(Path::new(&mount_path.to_string()))
    }

    fn default_mount_path(&self, product_type: QString) -> QString {
        let product_type = sanitize_mount_component(&product_type.to_string());
        let mount_path = mount_root_path().join(product_type);
        #[cfg(all(target_os = "linux", feature = "flatpak"))]
        if let Err(error) = std::fs::create_dir_all(&mount_path) {
            log::warn!(
                "failed to create default iFuse mount directory {}: {error}",
                mount_path.display()
            );
        }
        QString::from(mount_path.to_string_lossy().to_string())
    }

    fn mount(&mut self, udid: QString, mount_path: QString) {
        let udid = udid.to_string();
        let mount_path = mount_path.to_string();
        if udid.trim().is_empty() {
            self.set_status("", "Error: No device selected", true, false, false, "");
            return;
        }
        if mount_path.trim().is_empty() {
            self.set_status(
                &udid,
                "Error: No mount path selected",
                true,
                false,
                false,
                "",
            );
            return;
        }
        if !is_mount_path_supported(Path::new(&mount_path)) {
            self.set_status(
                &udid,
                &format!(
                    "Error: Unsupported mount directory. Choose a subdirectory of {}.",
                    mount_root_path().display()
                ),
                true,
                false,
                false,
                "",
            );
            return;
        }

        #[cfg(target_os = "windows")]
        {
            if Path::new(&mount_path).exists() {
                self.set_status(
                    &udid,
                    &format!("Error: Mount path must not exist on Windows: {mount_path}"),
                    true,
                    false,
                    false,
                    "",
                );
                return;
            }
            if let Err(error) = reserve_mount(&udid, &mount_path) {
                self.set_status(&udid, &error, true, false, false, "");
                return;
            }

            self.set_status(&udid, "Mounting device...", false, true, false, &mount_path);
            let q_thread = self.qt_thread();
            let state_udid = udid.clone();
            RUNTIME.spawn(async move {
                match IfuseBuilder::usb(udid.clone())
                    .mount_point(&mount_path)
                    .mount()
                    .await
                {
                    Ok(handle) => {
                        finish_embedded_mount(&udid, &mount_path, handle);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Device mounted successfully at: {mount_path}"),
                                false,
                                false,
                                true,
                                &mount_path,
                            );
                        });
                    }
                    Err(error) => {
                        cancel_mount_reservation(&mount_path);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Mount failed: {error:#}"),
                                true,
                                false,
                                false,
                                "",
                            );
                        });
                    }
                }
            });
            return;
        }

        #[cfg(target_os = "linux")]
        {
            if !Path::new(&mount_path).exists() {
                if let Err(error) = std::fs::create_dir_all(&mount_path) {
                    self.set_status(
                        &udid,
                        &format!("Error: Failed to create mount directory: {mount_path}: {error}"),
                        true,
                        false,
                        false,
                        "",
                    );
                    return;
                }
            }

            if let Err(error) = reserve_mount(&udid, &mount_path) {
                self.set_status(&udid, &error, true, false, false, "");
                return;
            }

            self.set_status(&udid, "Mounting device...", false, true, false, &mount_path);
            let q_thread = self.qt_thread();
            let state_udid = udid.clone();
            RUNTIME.spawn(async move {
                match mount_linux_device(&udid, &mount_path).await {
                    Ok(LinuxMount::Embedded(handle)) => {
                        finish_embedded_mount(&udid, &mount_path, handle);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Device mounted successfully at: {mount_path}"),
                                false,
                                false,
                                true,
                                &mount_path,
                            )
                        });
                    }
                    Ok(LinuxMount::External(location)) => {
                        finish_external_mount(&udid, &mount_path, location);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Device mounted successfully at: {mount_path}"),
                                false,
                                false,
                                true,
                                &mount_path,
                            )
                        });
                    }
                    Err(error) => {
                        error!("Mount failed: {error}");
                        cancel_mount_reservation(&mount_path);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Mount failed: {error}"),
                                true,
                                false,
                                false,
                                "",
                            )
                        });
                    }
                }
            });
        }
    }

    fn unmount(&mut self, mount_path: QString) {
        let mount_path = mount_path.to_string();
        if mount_path.trim().is_empty() {
            self.set_status("", "Error: No mount path selected", true, false, false, "");
            return;
        }
        let udid = udid_for_mount_path(&mount_path).unwrap_or_default();
        self.begin_unmount(udid, mount_path);
    }

    fn unmount_device(&mut self, udid: QString) {
        let udid = udid.to_string();
        let paths = mounted_paths_for_udid(&udid);
        if let Some(path) = paths.into_iter().next() {
            self.begin_unmount(udid, path);
        }
    }

    fn unmount_device_path(&mut self, udid: QString, mount_path: QString) {
        let udid = udid.to_string();
        let mount_path = mount_path.to_string();
        if !mount_path.trim().is_empty() {
            self.begin_unmount(udid, mount_path);
        }
    }

    fn begin_unmount(&mut self, udid: String, mount_path: String) {
        self.set_status(
            &udid,
            "Unmounting device...",
            false,
            true,
            true,
            &mount_path,
        );
        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            match unmount_path(&mount_path).await {
                Ok(()) => q_thread.queue(move |q| {
                    q.set_status(
                        &udid,
                        &format!("Device unmounted from {mount_path}"),
                        false,
                        false,
                        false,
                        "",
                    );
                }),
                Err(error) => q_thread.queue(move |q| {
                    q.set_status(
                        &udid,
                        &format!("Failed to unmount iFuse at {mount_path}. {error}"),
                        true,
                        false,
                        true,
                        &mount_path,
                    );
                }),
            }
        });
    }

    fn set_status(
        &mut self,
        udid: &str,
        message: &str,
        is_error: bool,
        busy: bool,
        mounted: bool,
        mount_path: &str,
    ) {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "busy", busy);
        qvariantmap_insert!(state, "mounted", mounted);
        qvariantmap_insert!(state, "mountPath", QString::from(mount_path));
        qvariantmap_insert!(state, "message", QString::from(message));
        qvariantmap_insert!(state, "isError", is_error);
        self.device_states.insert(udid.to_string(), state.clone());
        self.state = state;
        self.stateChanged();
        self.deviceStateChanged(QString::from(udid));
    }
}

fn default_state() -> QVariantMap {
    let mut state = QVariantMap::default();
    qvariantmap_insert!(state, "busy", false);
    qvariantmap_insert!(state, "mounted", false);
    qvariantmap_insert!(state, "mountPath", QString::default());
    qvariantmap_insert!(state, "message", QString::default());
    qvariantmap_insert!(state, "isError", false);
    state
}

#[cfg(target_os = "linux")]
async fn mount_linux_device(udid: &str, mount_path: &str) -> Result<LinuxMount, String> {
    #[cfg(feature = "flatpak")]
    {
        if host_ifuse_available().await? {
            info!("Using host ifuse through flatpak-spawn");
            let mut command = Command::new("flatpak-spawn");
            command.args(host_ifuse_mount_arguments(udid, mount_path));
            run_external_ifuse(&mut command).await?;
            return Ok(LinuxMount::External(ExternalMountLocation::Host));
        }
    }

    #[cfg(not(feature = "flatpak"))]
    if let Some(ifuse_path) = find_executable("ifuse") {
        info!("Using ifuse at: {}", ifuse_path.display());
        let mut command = Command::new(ifuse_path);
        command.arg("-u").arg(udid).arg(mount_path);
        run_external_ifuse(&mut command).await?;
        return Ok(LinuxMount::External(ExternalMountLocation::Local));
    }

    info!("Using ifuse-rs");
    IfuseBuilder::usb(udid.to_string())
        .mount_point(mount_path)
        .mount()
        .await
        .map(LinuxMount::Embedded)
        .map_err(|error| format!("{error:#}"))
}

#[cfg(all(target_os = "linux", feature = "flatpak"))]
fn host_ifuse_mount_arguments(udid: &str, mount_path: &str) -> Vec<std::ffi::OsString> {
    ["--host", "/usr/bin/env", "ifuse", "-u", udid, mount_path]
        .into_iter()
        .map(Into::into)
        .collect()
}

#[cfg(all(target_os = "linux", feature = "flatpak"))]
async fn host_ifuse_available() -> Result<bool, String> {
    let output = Command::new("flatpak-spawn")
        .arg("--host")
        .arg("sh")
        .arg("-lc")
        .arg("command -v ifuse >/dev/null")
        .output()
        .await
        .map_err(|error| format!("Failed to query host ifuse availability: {error}"))?;

    if output.status.success() {
        return Ok(true);
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if stderr.is_empty() {
        Ok(false)
    } else {
        Err(format!("Failed to query host ifuse availability: {stderr}"))
    }
}

#[cfg(target_os = "linux")]
async fn run_external_ifuse(command: &mut Command) -> Result<(), String> {
    let output = command
        .output()
        .await
        .map_err(|error| process_error_message(&error))?;
    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if stderr.is_empty() {
        Err(format!("ifuse exited with status {}", output.status))
    } else {
        Err(stderr)
    }
}

#[cfg(target_os = "windows")]
fn normalize_mount_path(path: &str) -> String {
    let absolute = std::path::absolute(path).unwrap_or_else(|_| PathBuf::from(path));
    let normalized = absolute.to_string_lossy().replace('/', "\\");
    normalized
        .strip_prefix(r"\\?\")
        .unwrap_or(&normalized)
        .trim_end_matches('\\')
        .to_lowercase()
}

#[cfg(target_os = "linux")]
fn normalize_mount_path(path: &str) -> String {
    std::path::absolute(path)
        .unwrap_or_else(|_| PathBuf::from(path))
        .to_string_lossy()
        .trim_end_matches('/')
        .to_string()
}

fn reserve_mount(udid: &str, mount_path: &str) -> Result<(), String> {
    let key = normalize_mount_path(mount_path);
    let mut mounts = MOUNTS.lock().unwrap();
    if mounts.contains_key(&key) {
        return Err(format!("Error: Mount path is already in use: {mount_path}"));
    }
    if mounts.values().any(|entry| entry.udid() == udid) {
        return Err("Error: This device already has an iDescriptor media mount".into());
    }
    mounts.insert(key, RegistryMount::Pending { udid: udid.into() });
    Ok(())
}

fn finish_embedded_mount(udid: &str, mount_path: &str, handle: MountHandle) {
    MOUNTS.lock().unwrap().insert(
        normalize_mount_path(mount_path),
        RegistryMount::Embedded {
            udid: udid.into(),
            handle,
        },
    );
}

#[cfg(target_os = "linux")]
fn finish_external_mount(udid: &str, mount_path: &str, location: ExternalMountLocation) {
    MOUNTS.lock().unwrap().insert(
        normalize_mount_path(mount_path),
        RegistryMount::External {
            udid: udid.into(),
            mount_path: mount_path.into(),
            location,
        },
    );
}

fn cancel_mount_reservation(mount_path: &str) {
    MOUNTS
        .lock()
        .unwrap()
        .remove(&normalize_mount_path(mount_path));
}

pub(crate) fn mounted_paths() -> Vec<String> {
    let mut paths = MOUNTS
        .lock()
        .unwrap()
        .values()
        .filter_map(RegistryMount::mount_path)
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

fn mounted_paths_for_udid(udid: &str) -> Vec<String> {
    MOUNTS
        .lock()
        .unwrap()
        .values()
        .filter(|entry| entry.udid() == udid)
        .filter_map(RegistryMount::mount_path)
        .collect()
}

fn udid_for_mount_path(mount_path: &str) -> Option<String> {
    MOUNTS
        .lock()
        .unwrap()
        .get(&normalize_mount_path(mount_path))
        .map(|entry| entry.udid().to_string())
}

pub(crate) async fn unmount_path(mount_path: &str) -> Result<(), String> {
    let key = normalize_mount_path(mount_path);
    let entry = MOUNTS.lock().unwrap().get(&key).cloned();
    let result = match entry {
        Some(RegistryMount::Embedded { handle, .. }) => {
            #[cfg(all(target_os = "linux", feature = "flatpak"))]
            {
                unmount_host_path(mount_path).await?;
                if let Err(error) = handle.unmount().await {
                    log::warn!(
                        "host mount {} was removed but the embedded FUSE session failed to stop: {error:#}",
                        mount_path
                    );
                }
                Ok(())
            }
            #[cfg(not(all(target_os = "linux", feature = "flatpak")))]
            {
                handle.unmount().await.map_err(|error| format!("{error:#}"))
            }
        }
        Some(RegistryMount::Pending { .. }) => Err("Mount is still starting".into()),
        #[cfg(target_os = "linux")]
        Some(RegistryMount::External { location, .. }) => match location {
            #[cfg(not(feature = "flatpak"))]
            ExternalMountLocation::Local => unmount_external_path(mount_path).await,
            #[cfg(feature = "flatpak")]
            ExternalMountLocation::Host => unmount_host_path(mount_path).await,
        },
        None => {
            #[cfg(target_os = "windows")]
            return Err("Mount is not managed by iDescriptor".into());
            #[cfg(all(target_os = "linux", not(feature = "flatpak")))]
            return unmount_external_path(mount_path).await;
            #[cfg(all(target_os = "linux", feature = "flatpak"))]
            return unmount_host_path(mount_path).await;
        }
    };

    finish_unmount(&key, &result);
    result
}

fn finish_unmount(key: &str, result: &Result<(), String>) {
    if result.is_ok() {
        MOUNTS.lock().unwrap().remove(key);
    }
}

pub(crate) fn shutdown_all_mounts(unmount_on_exit: bool) {
    if !unmount_on_exit {
        log::debug!("leaving daemonized external iFuse mounts active on exit");
        return;
    }

    let mount_paths = mounted_paths();
    RUNTIME.block_on(async {
        for mount_path in mount_paths {
            if let Err(error) = unmount_path(&mount_path).await {
                log::warn!("failed to unmount {mount_path} during shutdown: {error}");
            }
        }
    });
}

impl RegistryMount {
    fn udid(&self) -> &str {
        match self {
            Self::Pending { udid } | Self::Embedded { udid, .. } => udid,
            #[cfg(target_os = "linux")]
            Self::External { udid, .. } => udid,
        }
    }

    fn mount_path(&self) -> Option<String> {
        match self {
            Self::Pending { .. } => None,
            Self::Embedded { handle, .. } => {
                Some(handle.mount_point().to_string_lossy().into_owned())
            }
            #[cfg(target_os = "linux")]
            Self::External { mount_path, .. } => Some(mount_path.clone()),
        }
    }
}

#[cfg(all(target_os = "linux", not(feature = "flatpak")))]
async fn unmount_external_path(mount_path: &str) -> Result<(), String> {
    let unmount_bin = find_executable("fusermount")
        .or_else(|| find_executable("fusermount3"))
        .or_else(|| find_executable("umount"))
        .ok_or_else(|| "No unmount helper found.".to_string())?;
    let mut command = Command::new(&unmount_bin);
    if unmount_bin
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with("fusermount"))
    {
        command.arg("-u");
    }
    let output = command
        .arg(mount_path)
        .output()
        .await
        .map_err(|error| error.to_string())?;
    if output.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

#[cfg(all(target_os = "linux", feature = "flatpak"))]
async fn unmount_host_path(mount_path: &str) -> Result<(), String> {
    let helper = std::env::var_os("FUSERMOUNT_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/app/bin/idescriptor-fusermount3"));
    let output = Command::new(&helper)
        .arg("-u")
        .arg(mount_path)
        .output()
        .await
        .map_err(|error| {
            format!(
                "Failed to start Flatpak host unmount helper {}: {error}",
                helper.display()
            )
        })?;
    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            Err(format!(
                "Host fusermount3 exited with status {}",
                output.status
            ))
        } else {
            Err(stderr)
        }
    }
}

#[cfg(not(all(target_os = "linux", feature = "flatpak")))]
fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
}

fn sanitize_mount_component(value: &str) -> String {
    let sanitized: String = value
        .trim()
        .chars()
        .map(|character| match character {
            '/' | '\\' => '-',
            character if character.is_control() => '-',
            character => character,
        })
        .collect();

    if sanitized.is_empty() || sanitized == "." || sanitized == ".." {
        "iPhone".to_string()
    } else {
        sanitized
    }
}

#[cfg(all(target_os = "linux", feature = "flatpak"))]
fn mount_root_path() -> PathBuf {
    let app_data_path = cpp!(unsafe [] -> QString as "QString" {
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    });
    let mount_root = PathBuf::from(app_data_path.to_string()).join("mounts");
    if let Err(error) = std::fs::create_dir_all(&mount_root) {
        log::warn!(
            "failed to create Flatpak iFuse mount root {}: {error}",
            mount_root.display()
        );
    }
    mount_root
}

#[cfg(not(all(target_os = "linux", feature = "flatpak")))]
fn mount_root_path() -> PathBuf {
    home_dir().unwrap_or_else(|| PathBuf::from("."))
}

#[cfg(all(target_os = "linux", feature = "flatpak"))]
fn is_mount_path_supported(path: &Path) -> bool {
    path_is_within_mount_root(&mount_root_path(), path)
}

#[cfg(not(all(target_os = "linux", feature = "flatpak")))]
fn is_mount_path_supported(_path: &Path) -> bool {
    true
}

#[cfg(all(target_os = "linux", feature = "flatpak"))]
fn path_is_within_mount_root(root: &Path, candidate: &Path) -> bool {
    let Ok(root) = root.canonicalize() else {
        return false;
    };
    let Ok(candidate) = candidate.canonicalize() else {
        return false;
    };

    candidate.is_dir() && candidate != root && candidate.starts_with(root)
}

#[cfg(all(target_os = "linux", not(feature = "flatpak")))]
fn find_executable(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH")
        .and_then(|paths| find_executable_in(name, std::env::split_paths(&paths)))
}

#[cfg(all(target_os = "linux", not(feature = "flatpak")))]
fn find_executable_in(
    name: &str,
    directories: impl IntoIterator<Item = PathBuf>,
) -> Option<PathBuf> {
    directories
        .into_iter()
        .map(|directory| directory.join(name))
        .find(|candidate| is_executable(candidate))
}

#[cfg(all(target_os = "linux", not(feature = "flatpak")))]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.is_file()
        && std::fs::metadata(path)
            .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
}

#[cfg(target_os = "linux")]
fn process_error_message(error: &std::io::Error) -> String {
    match error.kind() {
        std::io::ErrorKind::NotFound => "Failed to start ifuse. Make sure it's installed.".into(),
        std::io::ErrorKind::TimedOut => "ifuse process timed out.".into(),
        _ => format!("Unknown error occurred. {error}"),
    }
}

#[cfg(test)]
mod tests {
    #[cfg(target_os = "windows")]
    use super::normalize_mount_path;

    #[cfg(target_os = "windows")]
    #[test]
    fn normalizes_windows_mount_keys() {
        assert_eq!(
            normalize_mount_path(r"C:\Mount\\"),
            normalize_mount_path("c:/mount")
        );
    }

    #[cfg(all(target_os = "linux", not(feature = "flatpak")))]
    #[test]
    fn finds_an_executable_in_supplied_paths() {
        let executable = std::env::current_exe().unwrap();
        let directory = executable.parent().unwrap().to_path_buf();
        let name = executable.file_name().unwrap().to_str().unwrap();
        assert_eq!(
            super::find_executable_in(name, [directory]),
            Some(executable)
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn tracks_external_mounts_and_retains_failed_unmounts() {
        let mount_path = format!(
            "/tmp/idescriptor-registry-test-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        );
        let key = super::normalize_mount_path(&mount_path);
        super::reserve_mount("test-udid", &mount_path).unwrap();

        let failed = Err("unmount failed".to_string());
        super::finish_unmount(&key, &failed);
        assert!(super::MOUNTS.lock().unwrap().contains_key(&key));

        #[cfg(feature = "flatpak")]
        let location = super::ExternalMountLocation::Host;
        #[cfg(not(feature = "flatpak"))]
        let location = super::ExternalMountLocation::Local;
        super::finish_external_mount("test-udid", &mount_path, location);

        assert!(super::mounted_paths().contains(&mount_path));
        assert_eq!(
            super::udid_for_mount_path(&mount_path).as_deref(),
            Some("test-udid")
        );

        super::finish_unmount(&key, &Ok(()));
        assert!(!super::MOUNTS.lock().unwrap().contains_key(&key));
    }

    #[cfg(all(target_os = "linux", feature = "flatpak"))]
    #[test]
    fn keeps_flatpak_host_ifuse_arguments_separate() {
        let arguments = super::host_ifuse_mount_arguments("test-udid", "/tmp/iPhone 7");
        let expected = [
            "--host",
            "/usr/bin/env",
            "ifuse",
            "-u",
            "test-udid",
            "/tmp/iPhone 7",
        ]
        .into_iter()
        .map(std::ffi::OsString::from)
        .collect::<Vec<_>>();
        assert_eq!(arguments, expected);
    }

    #[cfg(all(target_os = "linux", feature = "flatpak"))]
    #[test]
    fn accepts_only_existing_directories_below_flatpak_mount_root() {
        use std::time::{SystemTime, UNIX_EPOCH};

        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let test_directory = std::env::temp_dir().join(format!(
            "idescriptor-ifuse-path-test-{}-{unique}",
            std::process::id()
        ));
        let mount_root = test_directory.join("mounts");
        let valid_mount = mount_root.join("device");
        let outside_directory = test_directory.join("outside");
        let file = mount_root.join("not-a-directory");

        std::fs::create_dir_all(&valid_mount).unwrap();
        std::fs::create_dir_all(&outside_directory).unwrap();
        std::fs::write(&file, b"not a mount directory").unwrap();

        assert!(super::path_is_within_mount_root(&mount_root, &valid_mount));
        assert!(!super::path_is_within_mount_root(&mount_root, &mount_root));
        assert!(!super::path_is_within_mount_root(
            &mount_root,
            &outside_directory
        ));
        assert!(!super::path_is_within_mount_root(
            &mount_root,
            &mount_root.join("missing")
        ));
        assert!(!super::path_is_within_mount_root(&mount_root, &file));
        assert!(!super::path_is_within_mount_root(
            &mount_root,
            &valid_mount.join("../..").join("outside")
        ));

        let escaping_link = mount_root.join("escaping-link");
        std::os::unix::fs::symlink(&outside_directory, &escaping_link).unwrap();
        assert!(!super::path_is_within_mount_root(
            &mount_root,
            &escaping_link
        ));

        std::fs::remove_dir_all(&test_directory).unwrap();
    }
}
