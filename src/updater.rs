use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use cpp::cpp;
use log::{debug, error, info, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::{QString, QVariantMap};
#[cfg(target_os = "linux")]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use zupdater::{AssetPolicy, DownloadedUpdate, Release, Update, UpdateProcedure};

#[cfg(all(
    target_os = "linux",
    any(
        all(feature = "appimage", feature = "flatpak"),
        all(feature = "appimage", feature = "package_manager"),
        all(feature = "flatpak", feature = "package_manager"),
    )
))]
compile_error!(
    "Only one Linux distribution feature may be enabled: appimage, flatpak, or package_manager"
);

#[cfg(all(feature = "windows_store", not(target_os = "windows")))]
compile_error!("The windows_store feature is only supported on Windows");

#[cfg(all(
    any(feature = "appimage", feature = "flatpak", feature = "package_manager"),
    not(target_os = "linux")
))]
compile_error!("The appimage, flatpak, and package_manager features are only supported on Linux");

const FLATPAK_PAGE_URL: &str = "https://flathub.org/apps/com.idescriptor.idescriptor";
// TODO: Verify that this is the final published Flatpak/Flathub URL.

const WINDOWS_STORE_URI: &str = "ms-windows-store://search/?query=iDescriptor";
// TODO: Replace this search URI with the final Microsoft Store PDP URI and verify that it opens
// the exact iDescriptor listing once the product ID is assigned.

const WINDOWS_STORE_FALLBACK_URL: &str = "https://apps.microsoft.com/search?query=iDescriptor";
// TODO: Replace this search URL with the final public Microsoft Store listing URL.

cpp! {{
    #include <QCoreApplication>
    #include <QDesktopServices>
    #include <QDir>
    #include <QProcess>
    #include <QStandardPaths>
    #include <QUrl>
}}

#[allow(non_snake_case)]
#[derive(QObject, QtThreading, Default)]
pub struct Updater {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),
    update_available: qt_signal!(profile: QVariantMap),
    no_update_found: qt_signal!(),
    check_failed: qt_signal!(error: QString),
    download_progress: qt_signal!(downloaded_bytes: i64, total_bytes: i64, progress: f64),
    download_finished: qt_signal!(path: QString),
    download_failed: qt_signal!(error: QString),
    currentReleaseReady: qt_signal!(profile: QVariantMap),
    currentReleaseFailed: qt_signal!(error: QString),
    check_for_updates: qt_method!(fn(&mut self, manual: bool)),
    fetch_current_release: qt_method!(fn(&mut self)),
    download_update: qt_method!(fn(&mut self)),
    open_downloaded_update: qt_method!(fn(&self)),
    reveal_downloaded_update: qt_method!(fn(&self)),
    updater: Option<zupdater::Updater>,
    current_update: Option<Update>,
    downloaded_path: QString,
}

impl Updater {
    pub fn new_with_state() -> Self {
        let mut def = Self::default();
        def.state = Self::idle_state();
        def.updater = match Self::build_updater() {
            Ok(updater) => Some(updater),
            Err(err) => {
                let message = format!("Failed to initialize updater: {err}");
                error!("{message}");
                def.state = Self::error_state(message);
                None
            }
        };
        def
    }

    fn build_updater() -> anyhow::Result<zupdater::Updater> {
        let update_config = update_config();

        let mut builder = zupdater::Updater::builder()
            .application_name(crate::APP_LABEL)
            .current_version(env!("CARGO_PKG_VERSION"))
            .repo("iDescriptor/iDescriptor")
            .skip_prerelease(update_config.skip_prerelease)
            .is_portable(update_config.is_portable)
            .asset_policy(update_config.asset_policy)
            .package_manager_managed(update_config.package_manager_managed)
            .update_procedure(update_config.update_procedure);

        if let Some(message) = update_config.package_manager_managed_message {
            builder = builder.package_manager_managed_message(message);
        }

        Ok(builder.build()?)
    }

    fn check_for_updates(&mut self, manual: bool) {
        let Some(updater) = self.updater.take() else {
            let message = "Updater is not initialized".to_string();
            warn!("{message}");
            self.state = Self::error_state(message.clone());
            self.state_changed();
            if manual {
                self.check_failed(QString::from(message));
            }
            return;
        };

        self.state = Self::checking_state(manual);
        self.state_changed();

        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            debug!("Checking for updates");
            let result = updater.check_for_updates().await;

            q_thread.queue(move |t| {
                t.updater = Some(updater);

                match result {
                    Ok(Some(update)) => {
                        info!("Update available: {}", update.tag_name);
                        let profile = update_to_profile(&update);
                        t.current_update = Some(update);
                        t.downloaded_path = QString::default();
                        t.state = Self::update_available_state(&profile);
                        t.state_changed();
                        t.update_available(profile);
                    }
                    Ok(None) => {
                        info!("No update found");
                        t.current_update = None;
                        t.state = Self::idle_state();
                        t.state_changed();
                        if manual {
                            t.no_update_found();
                        }
                    }
                    Err(err) => {
                        let message = format!("{err}");
                        error!("Update check failed: {message}");
                        t.current_update = None;
                        t.state = Self::error_state(message.clone());
                        t.state_changed();
                        if manual {
                            t.check_failed(QString::from(message));
                        }
                    }
                }
            });
        });
    }

    fn fetch_current_release(&mut self) {
        let updater = match Self::build_updater() {
            Ok(updater) => updater,
            Err(err) => {
                let message = format!("Failed to initialize release notes lookup: {err}");
                warn!("{message}");
                self.currentReleaseFailed(QString::from(message));
                return;
            }
        };

        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            debug!("Fetching release notes for the current version");
            let result = updater.current_release().await;

            q_thread.queue(move |t| match result {
                Ok(Some(release)) => {
                    info!("Loaded release notes for {}", release.tag_name);
                    t.currentReleaseReady(release_to_profile(&release));
                }
                Ok(None) => {
                    let message = format!(
                        "No GitHub release matches the current version {}",
                        env!("CARGO_PKG_VERSION")
                    );
                    warn!("{message}");
                    t.currentReleaseFailed(QString::from(message));
                }
                Err(err) => {
                    let message = format!("Failed to load release notes: {err}");
                    warn!("{message}");
                    t.currentReleaseFailed(QString::from(message));
                }
            });
        });
    }

    fn download_update(&mut self) {
        let Some(update) = self.current_update.clone() else {
            let message = "No update is available to download".to_string();
            warn!("{message}");
            self.download_failed(QString::from(message));
            return;
        };

        let destination_dir = downloads_dir();
        self.state = Self::downloading_state(0, None);
        self.state_changed();

        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            info!(
                "Downloading update {} into {}",
                update.tag_name,
                destination_dir.display()
            );

            let progress_thread = q_thread.clone();
            let result: anyhow::Result<DownloadedUpdate> = async {
                let downloaded = update
                    .download_with_progress(&destination_dir, move |progress| {
                        let downloaded_bytes = progress.downloaded_bytes as i64;
                        let total_bytes =
                            progress.total_bytes.map(|value| value as i64).unwrap_or(-1);
                        let fraction = progress.fraction().unwrap_or(0.0);
                        let progress_thread = progress_thread.clone();

                        progress_thread.queue(move |t| {
                            t.state =
                                Self::downloading_state(downloaded_bytes, progress.total_bytes);
                            t.state_changed();
                            t.download_progress(downloaded_bytes, total_bytes, fraction);
                        });
                    })
                    .await?;

                prepare_downloaded_update(&update, downloaded).await
            }
            .await;

            q_thread.queue(move |t| match result {
                Ok(downloaded) => {
                    let path = QString::from(downloaded.path.to_string_lossy().to_string());
                    info!("Update downloaded: {}", downloaded.path.display());
                    t.downloaded_path = path.clone();
                    t.state = Self::downloaded_state(&downloaded);
                    t.state_changed();
                    t.download_finished(path);
                }
                Err(err) => {
                    let message = format!("{err}");
                    error!("Update download failed: {message}");
                    t.state = Self::error_state(message.clone());
                    t.state_changed();
                    t.download_failed(QString::from(message));
                }
            });
        });
    }

    fn open_downloaded_update(&self) {
        let quit_app = self
            .current_update
            .as_ref()
            .map(|update| update.update_procedure.quit_app)
            .unwrap_or(false);

        open_path(self.downloaded_path.clone(), quit_app);
    }

    fn reveal_downloaded_update(&self) {
        reveal_path(self.downloaded_path.clone());
    }

    fn idle_state() -> QVariantMap {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "checking", false);
        qvariantmap_insert!(state, "downloading", false);
        qvariantmap_insert!(state, "updateAvailable", false);
        qvariantmap_insert!(state, "downloaded", false);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "downloadedPath", QString::default());
        qvariantmap_insert!(state, "downloadedBytes", 0_i64);
        qvariantmap_insert!(state, "totalBytes", -1_i64);
        qvariantmap_insert!(state, "progress", 0.0_f64);
        state
    }

    fn checking_state(manual: bool) -> QVariantMap {
        let mut state = Self::idle_state();
        qvariantmap_insert!(state, "checking", true);
        qvariantmap_insert!(state, "manual", manual);
        state
    }

    fn update_available_state(profile: &QVariantMap) -> QVariantMap {
        let mut state = Self::idle_state();
        qvariantmap_insert!(state, "updateAvailable", true);
        qvariantmap_insert!(state, "profile", profile);
        state
    }

    fn downloading_state(downloaded_bytes: i64, total_bytes: Option<u64>) -> QVariantMap {
        let mut state = Self::idle_state();
        let total = total_bytes.map(|value| value as i64).unwrap_or(-1);
        let progress = total_bytes
            .filter(|value| *value > 0)
            .map(|value| downloaded_bytes as f64 / value as f64)
            .unwrap_or(0.0);

        qvariantmap_insert!(state, "downloading", true);
        qvariantmap_insert!(state, "downloadedBytes", downloaded_bytes);
        qvariantmap_insert!(state, "totalBytes", total);
        qvariantmap_insert!(state, "progress", progress);
        state
    }

    fn downloaded_state(downloaded: &DownloadedUpdate) -> QVariantMap {
        let mut state = Self::idle_state();
        qvariantmap_insert!(state, "downloaded", true);
        qvariantmap_insert!(
            state,
            "downloadedPath",
            QString::from(downloaded.path.to_string_lossy().to_string())
        );
        qvariantmap_insert!(state, "downloadedBytes", downloaded.bytes as i64);
        qvariantmap_insert!(
            state,
            "totalBytes",
            downloaded
                .asset
                .size
                .map(|value| value as i64)
                .unwrap_or(-1)
        );
        qvariantmap_insert!(state, "progress", 1.0_f64);
        state
    }

    fn error_state(error: String) -> QVariantMap {
        let mut state = Self::idle_state();
        qvariantmap_insert!(state, "error", QString::from(error));
        state
    }
}

async fn prepare_downloaded_update(
    update: &Update,
    downloaded: DownloadedUpdate,
) -> anyhow::Result<DownloadedUpdate> {
    if update.asset_policy != AssetPolicy::LinuxAppImage {
        return Ok(downloaded);
    }

    #[cfg(target_os = "linux")]
    {
        mark_appimage_executable(&downloaded.path).await?;
        return Ok(downloaded);
    }

    #[cfg(not(target_os = "linux"))]
    {
        anyhow::bail!("AppImage updates can only be prepared on Linux");
    }
}

#[cfg(target_os = "linux")]
async fn mark_appimage_executable(path: &Path) -> anyhow::Result<()> {
    let mut permissions = tokio::fs::metadata(path).await?.permissions();
    permissions.set_mode(0o755);
    tokio::fs::set_permissions(path, permissions).await?;
    Ok(())
}

fn update_to_profile(update: &Update) -> QVariantMap {
    let mut profile = QVariantMap::default();
    let asset = update.asset.as_ref();
    let channel = install_channel();

    qvariantmap_insert!(
        profile,
        "application_name",
        QString::from(update.application_name.clone())
    );
    qvariantmap_insert!(
        profile,
        "current_version",
        QString::from(update.current_version.to_string())
    );
    qvariantmap_insert!(
        profile,
        "version",
        QString::from(update.version.to_string())
    );
    qvariantmap_insert!(profile, "tag_name", QString::from(update.tag_name.clone()));
    qvariantmap_insert!(
        profile,
        "release_name",
        QString::from(update.release_name.clone().unwrap_or_default())
    );
    qvariantmap_insert!(profile, "body", QString::from(update.changelog.clone()));
    qvariantmap_insert!(
        profile,
        "changelog",
        QString::from(update.changelog.clone())
    );
    qvariantmap_insert!(
        profile,
        "release_url",
        QString::from(update.release_url.clone())
    );
    qvariantmap_insert!(
        profile,
        "published_at",
        QString::from(update.published_at.clone().unwrap_or_default())
    );
    qvariantmap_insert!(profile, "prerelease", update.prerelease);
    qvariantmap_insert!(
        profile,
        "delivery_kind",
        QString::from(channel.delivery_kind())
    );
    qvariantmap_insert!(
        profile,
        "external_update_url",
        QString::from(channel.external_update_url().unwrap_or_default())
    );
    qvariantmap_insert!(
        profile,
        "external_update_fallback_url",
        QString::from(channel.external_update_fallback_url().unwrap_or_default())
    );
    qvariantmap_insert!(
        profile,
        "package_manager_managed",
        update.package_manager_managed
    );
    qvariantmap_insert!(
        profile,
        "package_manager_managed_message",
        QString::from(
            update
                .package_manager_managed_message
                .clone()
                .unwrap_or_default()
        )
    );
    qvariantmap_insert!(profile, "is_portable", update.is_portable);
    qvariantmap_insert!(
        profile,
        "update_procedure_open_file",
        update.update_procedure.open_file
    );
    qvariantmap_insert!(
        profile,
        "update_procedure_open_file_dir",
        update.update_procedure.open_file_dir
    );
    qvariantmap_insert!(
        profile,
        "update_procedure_quit_app",
        update.update_procedure.quit_app
    );
    qvariantmap_insert!(
        profile,
        "update_procedure_informative_text",
        QString::from(update.update_procedure.informative_text.clone())
    );
    qvariantmap_insert!(
        profile,
        "update_procedure_text",
        QString::from(update.update_procedure.text.clone())
    );
    qvariantmap_insert!(
        profile,
        "file_name",
        QString::from(asset.map(|asset| asset.name.clone()).unwrap_or_default())
    );
    qvariantmap_insert!(
        profile,
        "asset_label",
        QString::from(
            asset
                .and_then(|asset| asset.label.clone())
                .unwrap_or_default()
        )
    );
    qvariantmap_insert!(
        profile,
        "browser_download_url",
        QString::from(
            asset
                .map(|asset| asset.download_url.clone())
                .unwrap_or_default()
        )
    );
    qvariantmap_insert!(
        profile,
        "asset_size",
        asset
            .and_then(|asset| asset.size)
            .map(|value| value as i64)
            .unwrap_or(-1)
    );

    profile
}

fn release_to_profile(release: &Release) -> QVariantMap {
    let mut profile = QVariantMap::default();
    qvariantmap_insert!(profile, "tag_name", QString::from(release.tag_name.clone()));
    qvariantmap_insert!(
        profile,
        "release_name",
        QString::from(release.release_name.clone().unwrap_or_default())
    );
    qvariantmap_insert!(profile, "body", QString::from(release.changelog.clone()));
    qvariantmap_insert!(
        profile,
        "release_url",
        QString::from(release.release_url.clone())
    );
    qvariantmap_insert!(profile, "prerelease", release.prerelease);
    qvariantmap_insert!(
        profile,
        "published_at",
        QString::from(release.published_at.clone().unwrap_or_default())
    );
    profile
}

struct UpdaterSetup {
    update_procedure: UpdateProcedure,
    is_portable: bool,
    asset_policy: AssetPolicy,
    package_manager_managed: bool,
    package_manager_managed_message: Option<String>,
    skip_prerelease: bool,
}

fn update_config() -> UpdaterSetup {
    let channel = install_channel();

    let update_procedure = match channel {
        InstallChannel::WindowsInstaller => UpdateProcedure {
            open_file: true,
            open_file_dir: false,
            quit_app: true,
            informative_text: "The application will now quit to install the update.".to_string(),
            text: "Do you want to install the downloaded update now?".to_string(),
        },
        InstallChannel::WindowsPortable => UpdateProcedure {
            open_file: false,
            open_file_dir: true,
            quit_app: false,
            informative_text:
                "New portable version downloaded, app location will be shown after this message."
                    .to_string(),
            text: "New portable version downloaded".to_string(),
        },
        InstallChannel::MacDmg => UpdateProcedure {
            open_file: true,
            open_file_dir: false,
            quit_app: true,
            informative_text: "The application will now quit and open .dmg file downloaded to \"Downloads\". From there you can drag it to Applications to install.".to_string(),
            text: "Update downloaded would you like to quit and install the update?".to_string(),
        },
        InstallChannel::LinuxAppImage => UpdateProcedure {
            open_file: true,
            open_file_dir: false,
            quit_app: true,
            informative_text: "AppImages we ship are not updateable. New version is downloaded to \"Downloads\". You can start using the new version by launching it from there. You can delete this AppImage version if you like.".to_string(),
            text: "Update downloaded would you like to quit and open the new version?".to_string(),
        },
        InstallChannel::WindowsStore
        | InstallChannel::Flatpak
        | InstallChannel::CustomPackageManager
        | InstallChannel::NativeLinux => UpdateProcedure::default(),
    };

    UpdaterSetup {
        update_procedure,
        is_portable: channel == InstallChannel::WindowsPortable,
        asset_policy: channel.asset_policy(),
        package_manager_managed: channel.is_externally_managed(),
        package_manager_managed_message: if channel == InstallChannel::CustomPackageManager {
            custom_package_manager_message(option_env!("IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE"))
        } else {
            None
        },
        skip_prerelease: true,
    }
}

fn custom_package_manager_message(message: Option<&str>) -> Option<String> {
    message
        .map(str::trim)
        .filter(|message| !message.is_empty())
        .map(str::to_string)
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum InstallChannel {
    WindowsInstaller,
    WindowsPortable,
    WindowsStore,
    MacDmg,
    LinuxAppImage,
    Flatpak,
    CustomPackageManager,
    NativeLinux,
}

impl InstallChannel {
    fn asset_policy(self) -> AssetPolicy {
        match self {
            Self::WindowsInstaller => AssetPolicy::WindowsInstaller,
            Self::WindowsPortable => AssetPolicy::WindowsPortable,
            Self::MacDmg => AssetPolicy::MacDmg,
            Self::LinuxAppImage => AssetPolicy::LinuxAppImage,
            Self::WindowsStore | Self::Flatpak | Self::CustomPackageManager | Self::NativeLinux => {
                AssetPolicy::NoDirectDownload
            }
        }
    }

    fn delivery_kind(self) -> &'static str {
        match self {
            Self::WindowsStore => "windowsStore",
            Self::Flatpak => "flatpak",
            Self::CustomPackageManager => "packageManager",
            Self::LinuxAppImage => "appImage",
            Self::NativeLinux => "releasePage",
            Self::WindowsInstaller | Self::WindowsPortable | Self::MacDmg => "direct",
        }
    }

    fn is_externally_managed(self) -> bool {
        matches!(
            self,
            Self::WindowsStore | Self::Flatpak | Self::CustomPackageManager
        )
    }

    fn external_update_url(self) -> Option<&'static str> {
        match self {
            Self::Flatpak => Some(FLATPAK_PAGE_URL),
            Self::WindowsStore => Some(WINDOWS_STORE_URI),
            _ => None,
        }
    }

    fn external_update_fallback_url(self) -> Option<&'static str> {
        match self {
            Self::WindowsStore => Some(WINDOWS_STORE_FALLBACK_URL),
            _ => None,
        }
    }
}

fn install_channel() -> InstallChannel {
    #[cfg(target_os = "windows")]
    {
        if cfg!(feature = "windows_store") {
            return InstallChannel::WindowsStore;
        }

        return if is_windows_portable_install() {
            InstallChannel::WindowsPortable
        } else {
            InstallChannel::WindowsInstaller
        };
    }

    #[cfg(target_os = "macos")]
    {
        return InstallChannel::MacDmg;
    }

    #[cfg(target_os = "linux")]
    {
        return linux_install_channel(
            cfg!(feature = "appimage"),
            cfg!(feature = "flatpak"),
            cfg!(feature = "package_manager"),
        );
    }

    #[allow(unreachable_code)]
    InstallChannel::NativeLinux
}

fn linux_install_channel(
    is_appimage: bool,
    is_flatpak: bool,
    is_package_manager: bool,
) -> InstallChannel {
    if is_flatpak {
        InstallChannel::Flatpak
    } else if is_appimage {
        InstallChannel::LinuxAppImage
    } else if is_package_manager {
        InstallChannel::CustomPackageManager
    } else {
        InstallChannel::NativeLinux
    }
}

#[cfg(target_os = "windows")]
fn is_windows_portable_install() -> bool {
    let Ok(exe_path) = std::env::current_exe() else {
        return false;
    };
    let exe_path = exe_path.to_string_lossy().to_lowercase();
    let program_dirs = [
        std::env::var("ProgramFiles").ok(),
        std::env::var("ProgramFiles(x86)").ok(),
        std::env::var("LOCALAPPDATA")
            .ok()
            .map(|path| format!("{path}\\Programs")),
    ];

    !program_dirs
        .iter()
        .flatten()
        .map(|path| path.to_lowercase())
        .any(|path| exe_path.starts_with(&path))
}

fn downloads_dir() -> PathBuf {
    let path = cpp!(unsafe [] -> QString as "QString" {
        QString path = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        if (path.isEmpty()) {
            path = QDir::homePath();
        }
        path += QStringLiteral("/iDescriptor");
        QDir().mkpath(path);
        return path;
    });

    PathBuf::from(path.to_string())
}

fn open_path(path: QString, quit_app: bool) {
    if path.to_string().is_empty() {
        warn!("Cannot open update: downloaded path is empty");
        return;
    }

    cpp!(unsafe [path as "QString", quit_app as "bool"] {
        #ifdef Q_OS_LINUX
            if (path.endsWith(QStringLiteral(".AppImage"), Qt::CaseInsensitive)) {
                bool opened = QProcess::startDetached(path, QStringList());
                if (opened && quit_app) {
                    QCoreApplication::quit();
                }
                return;
            }
        #endif
        bool opened = QDesktopServices::openUrl(QUrl::fromLocalFile(path));
        if (opened && quit_app) {
            QCoreApplication::quit();
        }
    });
}

fn reveal_path(path: QString) {
    let path_string = path.to_string();
    if path_string.is_empty() {
        warn!("Cannot reveal update: downloaded path is empty");
        return;
    }

    let dir = Path::new(&path_string)
        .parent()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or(path_string);

    cpp!(unsafe [dir as "QString"] {
        QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn linux_channel_requires_appimage_feature_signal() {
        assert_eq!(
            linux_install_channel(false, false, false),
            InstallChannel::NativeLinux
        );
        assert_eq!(
            linux_install_channel(true, false, false),
            InstallChannel::LinuxAppImage
        );
    }

    #[test]
    fn externally_managed_channels_do_not_select_release_assets() {
        for channel in [
            InstallChannel::Flatpak,
            InstallChannel::WindowsStore,
            InstallChannel::CustomPackageManager,
        ] {
            assert_eq!(channel.asset_policy(), AssetPolicy::NoDirectDownload);
            assert!(channel.is_externally_managed());
        }
    }

    #[test]
    fn only_store_channels_expose_external_update_urls() {
        assert_eq!(
            InstallChannel::Flatpak.external_update_url(),
            Some(FLATPAK_PAGE_URL)
        );
        assert_eq!(
            InstallChannel::WindowsStore.external_update_url(),
            Some(WINDOWS_STORE_URI)
        );
        assert_eq!(
            InstallChannel::CustomPackageManager.external_update_url(),
            None
        );
    }

    #[test]
    fn custom_package_manager_message_ignores_missing_or_blank_values() {
        assert_eq!(custom_package_manager_message(None), None);
        assert_eq!(custom_package_manager_message(Some("   ")), None);
        assert_eq!(
            custom_package_manager_message(Some("  Update with yay or paru.  ")),
            Some("Update with yay or paru.".to_string())
        );
    }

    #[cfg(feature = "package_manager")]
    #[test]
    fn package_manager_config_uses_compiled_custom_message() {
        assert_eq!(
            update_config().package_manager_managed_message,
            custom_package_manager_message(option_env!("IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE"))
        );
    }

    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn downloaded_appimage_is_marked_executable() -> anyhow::Result<()> {
        let test_dir =
            std::env::temp_dir().join(format!("idescriptor-updater-test-{}", std::process::id()));
        std::fs::create_dir_all(&test_dir)?;
        let appimage_path = test_dir.join("iDescriptor-Linux_x86_64.AppImage");
        std::fs::write(&appimage_path, b"appimage-test")?;
        let mut initial_permissions = std::fs::metadata(&appimage_path)?.permissions();
        initial_permissions.set_mode(0o644);
        std::fs::set_permissions(&appimage_path, initial_permissions)?;

        mark_appimage_executable(&appimage_path).await?;

        assert_ne!(
            std::fs::metadata(&appimage_path)?.permissions().mode() & 0o111,
            0
        );

        std::fs::remove_dir_all(test_dir)?;
        Ok(())
    }
}
