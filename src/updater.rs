use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use cpp::cpp;
use log::{debug, error, info, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::{QString, QVariantMap};
use std::path::{Path, PathBuf};
use zupdater::{DownloadedUpdate, Platform, Release, Update, UpdateProcedure};

cpp! {{
    #include <QCoreApplication>
    #include <QDesktopServices>
    #include <QDir>
    #include <QProcess>
    #include <QStandardPaths>
    #include <QUrl>
}}

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

        Ok(zupdater::Updater::builder()
            .application_name(crate::APP_LABEL)
            .current_version(env!("CARGO_PKG_VERSION"))
            .repo("iDescriptor/iDescriptor")
            .skip_prerelease(update_config.skip_prerelease)
            .is_portable(update_config.is_portable)
            .package_manager_managed(update_config.package_manager_managed)
            .update_procedure(update_config.update_procedure)
            .package_manager_managed_message(update_config.package_manager_managed_message)
            .build()?)
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
            let result = update
                .download_with_progress(&destination_dir, move |progress| {
                    let downloaded_bytes = progress.downloaded_bytes as i64;
                    let total_bytes = progress.total_bytes.map(|value| value as i64).unwrap_or(-1);
                    let fraction = progress.fraction().unwrap_or(0.0);
                    let progress_thread = progress_thread.clone();

                    progress_thread.queue(move |t| {
                        t.state = Self::downloading_state(downloaded_bytes, progress.total_bytes);
                        t.state_changed();
                        t.download_progress(downloaded_bytes, total_bytes, fraction);
                    });
                })
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

fn update_to_profile(update: &Update) -> QVariantMap {
    let mut profile = QVariantMap::default();
    let asset = update.asset.as_ref();

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
    package_manager_managed: bool,
    skip_prerelease: bool,
    package_manager_managed_message: String,
}

fn update_config() -> UpdaterSetup {
    let is_portable = is_portable_build();
    let package_manager_managed = is_package_manager_managed();
    let platform = zupdater::Updater::detect_platform().ok();

    let update_procedure = match platform {
        Some(Platform::Windows) => UpdateProcedure {
            open_file: !is_portable,
            open_file_dir: is_portable,
            quit_app: !is_portable,
            informative_text: if is_portable {
                "New portable version downloaded, app location will be shown after this message."
                    .to_string()
            } else {
                "The application will now quit to install the update.".to_string()
            },
            text: if is_portable {
                "New portable version downloaded".to_string()
            } else {
                "Do you want to install the downloaded update now?".to_string()
            },
        },
        Some(Platform::MacOs) => UpdateProcedure {
            open_file: true,
            open_file_dir: false,
            quit_app: true,
            informative_text: "The application will now quit and open .dmg file downloaded to \"Downloads\". From there you can drag it to Applications to install.".to_string(),
            text: "Update downloaded would you like to quit and install the update?".to_string(),
        },
        Some(Platform::Linux) => UpdateProcedure {
            open_file: true,
            open_file_dir: false,
            quit_app: true,
            informative_text: "AppImages we ship are not updateable. New version is downloaded to \"Downloads\". You can start using the new version by launching it from there. You can delete this AppImage version if you like.".to_string(),
            text: "Update downloaded would you like to quit and open the new version?".to_string(),
        },
        None => UpdateProcedure::default(),
    };

    UpdaterSetup {
        update_procedure,
        is_portable,
        package_manager_managed,
        skip_prerelease: true,
        package_manager_managed_message: package_manager_message(),
    }
}

fn is_portable_build() -> bool {
    #[cfg(target_os = "windows")]
    {
        is_windows_portable_install()
    }

    #[cfg(not(target_os = "windows"))]
    {
        false
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

fn is_package_manager_managed() -> bool {
    cfg!(target_os = "linux") && option_env!("PACKAGE_MANAGER_MANAGED").is_some()
}

fn package_manager_message() -> String {
    let hint = option_env!("PACKAGE_MANAGER_HINT").unwrap_or("your package manager");

    format!(
        "You seem to have installed iDescriptor using a package manager. Please use {hint} to update it."
    )
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
