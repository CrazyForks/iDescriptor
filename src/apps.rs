use crate::{RUNTIME, device_ctx::get_device, qt_threading::QtThreading, qvariantmap_insert};
use anyhow::Context;
use idevice::utils::installation::install_package_with_callback;
use ipatool::error::IpaToolError;
use ipatool::{DownloadArgs, IpaTool};
use log::{debug, error, info};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::QVariantMap;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{
        Arc,
        mpsc::{self, SyncSender},
    },
};
use tokio::task::JoinHandle;

enum AuthCodeResponse {
    Code(String),
    Cancelled,
}

struct TaskDirectory {
    path: PathBuf,
}

impl TaskDirectory {
    async fn create(parent: &Path, task_id: &str) -> anyhow::Result<Self> {
        let path = parent.join(format!(".idescriptor-{task_id}"));
        tokio::fs::create_dir_all(&path)
            .await
            .with_context(|| format!("Failed to create temporary directory {}", path.display()))?;
        Ok(Self { path })
    }
}

impl Drop for TaskDirectory {
    fn drop(&mut self) {
        if let Err(err) = std::fs::remove_dir_all(&self.path)
            && err.kind() != std::io::ErrorKind::NotFound
        {
            debug!(
                "Failed to remove temporary IPA directory {}: {err}",
                self.path.display()
            );
        }
    }
}
#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct Apps {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY  state_changed),
    state_changed: qt_signal!(),
    ipa_tool: Option<Arc<IpaTool>>,
    sign_in_busy: bool,
    pending_auth_code: Option<(String, SyncSender<AuthCodeResponse>)>,
    tasks: HashMap<String, JoinHandle<()>>,
    init: qt_method!(fn(&mut self, load_saved_account: bool)),
    sign_in: qt_method!(fn(&mut self, email: QString, password: QString)),
    auth_code_received: qt_method!(fn(&mut self, request_id: QString, code: QString)),
    auth_code_cancelled: qt_method!(fn(&mut self, request_id: QString)),
    sign_out: qt_method!(fn(&mut self)),
    search: qt_method!(fn(&mut self, term: QString)),
    download_ipa: qt_method!(fn(&mut self, bundle_id: QString, output_path: QString) -> QString),
    install_app: qt_method!(fn(&mut self, bundle_id: QString, udid: QString) -> QString),
    cancel_task: qt_method!(fn(&mut self, task_id: QString)),
    authCodeRequested: qt_signal!(request_id: QString, email: QString),
    signInFinished: qt_signal!(success: bool, error: QString),
    search_ready: qt_signal!(search_term : QString, success: bool, res: QString),
    downloadIpaProgress: qt_signal!(task_id: QString, progress: f64),
    downloadIpaFinished: qt_signal!(task_id: QString, success: bool, path: QString, error: QString),
    installAppProgress: qt_signal!(task_id: QString, progress: f64, phase: QString),
    installAppFinished: qt_signal!(task_id: QString, success: bool, error: QString),
}

impl Drop for Apps {
    fn drop(&mut self) {
        for (_, task) in self.tasks.drain() {
            task.abort();
        }
    }
}

impl Apps {
    pub fn new_with_state() -> Self {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "init", false);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "email", QString::default());
        qvariantmap_insert!(state, "signInBusy", false);
        qvariantmap_insert!(state, "authCodePending", false);

        let mut def = Self::default();
        def.state = state;
        def
    }

    fn set_state(&mut self, init: bool, email: QString, error: QString) {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "init", init);
        qvariantmap_insert!(state, "error", error);
        qvariantmap_insert!(state, "email", email);
        qvariantmap_insert!(state, "signInBusy", self.sign_in_busy);
        qvariantmap_insert!(state, "authCodePending", self.pending_auth_code.is_some());
        self.state = state;
        self.state_changed();
    }

    fn init(&mut self, load_saved_account: bool) {
        let tool = match IpaTool::new_default() {
            Ok(tool) => tool,
            Err(err) => {
                error!("Error creating IpaTool: {err}");
                self.set_state(true, QString::default(), QString::from(format!("{}", err)));
                return;
            }
        };

        if !load_saved_account {
            self.ipa_tool = Some(Arc::new(tool));
            self.set_state(true, QString::default(), QString::default());
            return;
        }

        let account_info = tool.account_info();
        self.ipa_tool = Some(Arc::new(tool));

        match account_info {
            Ok(maybe_acc) => {
                let acc = maybe_acc.unwrap_or_default();

                self.set_state(true, QString::from(acc.email), QString::default());
            }
            Err(err) => {
                self.set_state(true, QString::default(), QString::from(format!("{}", err)));
            }
        };
    }

    fn sign_in(&mut self, email: QString, password: QString) {
        if self.sign_in_busy {
            self.signInFinished(false, QString::from("Sign in is already in progress."));
            return;
        }

        self.sign_in_busy = true;
        self.set_state(true, QString::default(), QString::default());

        let email_string = email.to_string();
        let password_string = password.to_string();
        let Some(tool) = self.ipa_tool.clone() else {
            self.sign_in_busy = false;
            self.set_state(
                true,
                QString::default(),
                QString::from("IpaTool not initialized"),
            );
            self.signInFinished(false, QString::from("IpaTool not initialized"));
            return;
        };

        let q_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let q_thread_for_cb = q_thread.clone();
            let email_for_cb = email_string.clone();
            let auth_code_cb: Box<dyn Fn() -> ipatool::Result<String> + Send + Sync> =
                Box::new(move || {
                    let request_id = uuid::Uuid::new_v4().to_string();
                    let (tx, rx) = mpsc::sync_channel::<AuthCodeResponse>(1);
                    let qt = q_thread_for_cb.clone();
                    let request_id_for_qt = request_id.clone();
                    let email_for_qt = email_for_cb.clone();

                    qt.queue(move |apps| {
                        if let Some((_old_id, old_tx)) = apps.pending_auth_code.take() {
                            let _ = old_tx.send(AuthCodeResponse::Cancelled);
                        }

                        apps.pending_auth_code = Some((request_id_for_qt.clone(), tx));
                        apps.set_state(true, QString::default(), QString::default());
                        apps.authCodeRequested(
                            QString::from(request_id_for_qt),
                            QString::from(email_for_qt),
                        );
                    });

                    match rx.recv() {
                        Ok(AuthCodeResponse::Code(code)) if !code.is_empty() => Ok(code),
                        Ok(AuthCodeResponse::Code(_))
                        | Ok(AuthCodeResponse::Cancelled)
                        | Err(_) => Err(IpaToolError::AuthCodeRequired),
                    }
                });

            let result: ipatool::Result<(Arc<IpaTool>, String)> = async {
                tool.login(&email_string, &password_string, Some(auth_code_cb), None)
                    .await?;

                let account_email = tool
                    .account_info()?
                    .map(|acc| acc.email)
                    .unwrap_or_else(|| email_string.clone());

                Ok((tool, account_email))
            }
            .await;

            q_thread.queue(move |apps| {
                apps.sign_in_busy = false;
                if let Some((_id, tx)) = apps.pending_auth_code.take() {
                    let _ = tx.send(AuthCodeResponse::Cancelled);
                }

                match result {
                    Ok((tool, account_email)) => {
                        apps.ipa_tool = Some(tool);
                        apps.set_state(true, QString::from(account_email), QString::default());
                        apps.signInFinished(true, QString::default());
                    }
                    Err(err) => {
                        let error = QString::from(format!("{}", err));
                        debug!("Sign in failed: {}", error.to_string());
                        apps.set_state(true, QString::default(), error.clone());
                        apps.signInFinished(false, error);
                    }
                }
            });
        });
    }

    fn auth_code_received(&mut self, request_id: QString, code: QString) {
        let request_id = request_id.to_string();
        let code = code.to_string().trim().to_string();

        let Some((pending_id, tx)) = self.pending_auth_code.take() else {
            return;
        };

        if pending_id != request_id {
            self.pending_auth_code = Some((pending_id, tx));
            return;
        }

        let _ = tx.send(AuthCodeResponse::Code(code));
        //self.set_state(true, QString::default(), QString::default());
    }

    fn auth_code_cancelled(&mut self, request_id: QString) {
        let request_id = request_id.to_string();

        let Some((pending_id, tx)) = self.pending_auth_code.take() else {
            return;
        };

        if pending_id != request_id {
            self.pending_auth_code = Some((pending_id, tx));
            return;
        }

        let _ = tx.send(AuthCodeResponse::Cancelled);
        // self.set_state(true, QString::default(), QString::default());
    }

    // DOES NOTHING IF CALLED BEFORE CALLING `init`
    fn search(&mut self, term: QString) {
        let Some(tool) = &self.ipa_tool else {
            eprintln!("IpaTool not initialized");
            return;
        };
        let tool = tool.clone();
        let q_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let serialized: anyhow::Result<String> = async {
                let apps = tool.search(&term.to_string(), 20).await?;
                Ok(serde_json::to_string(&apps)?)
            }
            .await;

            match serialized {
                Ok(serialized) => {
                    println!(
                        "Search successful for term '{}', result: {}",
                        term, serialized
                    );
                    q_thread.queue(|s| s.search_ready(term, true, QString::from(serialized)));
                }
                // FIXME: also return the error
                Err(err) => {
                    println!("Error in ipatool search {}", err.to_string());
                    q_thread.queue(|s| s.search_ready(term, false, QString::default()));
                }
            };
        });
    }

    fn download_ipa(&mut self, bundle_id: QString, output_path: QString) -> QString {
        let Some(tool) = self.ipa_tool.clone() else {
            return QString::default();
        };

        let bundle_id = bundle_id.to_string();
        if bundle_id.trim().is_empty() {
            return QString::default();
        }

        let output_path = PathBuf::from(output_path.to_string());
        let task_id = uuid::Uuid::new_v4().to_string();
        let task_id_for_task = task_id.clone();
        let q_thread = self.qt_thread();

        let task = RUNTIME.spawn(async move {
            let result: anyhow::Result<String> = async {
                tokio::fs::create_dir_all(&output_path)
                    .await
                    .with_context(|| {
                        format!(
                            "Failed to create IPA download directory {}",
                            output_path.display()
                        )
                    })?;

                let task_dir = TaskDirectory::create(&output_path, &task_id_for_task).await?;
                let progress_qt = q_thread.clone();
                let progress_task_id = task_id_for_task.clone();
                let downloaded_path = tool
                    .download_with_progress(
                        DownloadArgs {
                            bundle_id,
                            output_path: Some(task_dir.path.to_string_lossy().into_owned()),
                            external_version_id: None,
                            acquire_license: false,
                        },
                        move |downloaded, total| {
                            let progress = total
                                .filter(|total| *total > 0)
                                .map(|total| downloaded as f64 / total as f64)
                                .unwrap_or(-1.0);
                            let id = progress_task_id.clone();
                            progress_qt.queue(move |apps| {
                                apps.downloadIpaProgress(QString::from(id), progress);
                            });
                        },
                    )
                    .await?;

                let downloaded_path = PathBuf::from(downloaded_path);
                let file_name = downloaded_path
                    .file_name()
                    .context("The downloaded IPA path has no file name")?;
                let destination = output_path.join(file_name);
                if destination.exists() {
                    std::fs::remove_file(&destination).with_context(|| {
                        format!("Failed to replace IPA at {}", destination.display())
                    })?;
                }
                std::fs::rename(&downloaded_path, &destination)
                    .with_context(|| format!("Failed to save IPA to {}", destination.display()))?;

                Ok(destination.to_string_lossy().into_owned())
            }
            .await;

            let finished_task_id = task_id_for_task.clone();
            q_thread.queue(move |apps| {
                if apps.tasks.remove(&finished_task_id).is_none() {
                    return;
                }

                match result {
                    Ok(path) => {
                        info!("IPA download completed: {path}");
                        apps.downloadIpaFinished(
                            QString::from(finished_task_id),
                            true,
                            QString::from(path),
                            QString::default(),
                        );
                    }
                    Err(err) => {
                        error!("IPA download failed: {err:#}");
                        apps.downloadIpaFinished(
                            QString::from(finished_task_id),
                            false,
                            QString::default(),
                            QString::from(format!("{err:#}")),
                        );
                    }
                }
            });
        });

        self.tasks.insert(task_id.clone(), task);
        QString::from(task_id)
    }

    fn install_app(&mut self, bundle_id: QString, udid: QString) -> QString {
        let Some(tool) = self.ipa_tool.clone() else {
            return QString::default();
        };

        let bundle_id = bundle_id.to_string();
        let udid = udid.to_string();
        if bundle_id.trim().is_empty() || udid.trim().is_empty() {
            return QString::default();
        }

        let task_id = uuid::Uuid::new_v4().to_string();
        let task_id_for_task = task_id.clone();
        let q_thread = self.qt_thread();

        let task = RUNTIME.spawn(async move {
            let result: anyhow::Result<()> = async {
                let device = get_device(&udid).await?;
                let task_dir =
                    TaskDirectory::create(&std::env::temp_dir(), &task_id_for_task).await?;
                let progress_qt = q_thread.clone();
                let progress_task_id = task_id_for_task.clone();
                let ipa_path = tool
                    .download_with_progress(
                        DownloadArgs {
                            bundle_id,
                            output_path: Some(task_dir.path.to_string_lossy().into_owned()),
                            external_version_id: None,
                            acquire_license: true,
                        },
                        move |downloaded, total| {
                            let progress = total
                                .filter(|total| *total > 0)
                                .map(|total| (downloaded as f64 / total as f64) * 0.5)
                                .unwrap_or(-1.0);
                            let id = progress_task_id.clone();
                            progress_qt.queue(move |apps| {
                                apps.installAppProgress(
                                    QString::from(id),
                                    progress,
                                    QString::from("download"),
                                );
                            });
                        },
                    )
                    .await
                    .context("Failed to download the IPA")?;

                let installing_qt = q_thread.clone();
                let installing_task_id = task_id_for_task.clone();
                installing_qt.queue(move |apps| {
                    apps.installAppProgress(
                        QString::from(installing_task_id),
                        0.5,
                        QString::from("install"),
                    );
                });

                let provider = device.provider.lock().await;
                let callback_qt = q_thread.clone();
                let callback_task_id = task_id_for_task.clone();
                install_package_with_callback(
                    provider.as_ref(),
                    &ipa_path,
                    None,
                    move |(percentage, ())| {
                        let qt = callback_qt.clone();
                        let id = callback_task_id.clone();
                        async move {
                            let progress = 0.5 + (percentage.min(100) as f64 / 200.0);
                            qt.queue(move |apps| {
                                apps.installAppProgress(
                                    QString::from(id),
                                    progress,
                                    QString::from("install"),
                                );
                            });
                        }
                    },
                    (),
                )
                .await
                .context("Failed to install the IPA")?;

                Ok(())
            }
            .await;

            let finished_task_id = task_id_for_task.clone();
            q_thread.queue(move |apps| {
                if apps.tasks.remove(&finished_task_id).is_none() {
                    return;
                }

                match result {
                    Ok(()) => {
                        info!("App installation completed for device {udid}");
                        apps.installAppFinished(
                            QString::from(finished_task_id),
                            true,
                            QString::default(),
                        );
                    }
                    Err(err) => {
                        error!("App installation failed for device {udid}: {err:#}");
                        apps.installAppFinished(
                            QString::from(finished_task_id),
                            false,
                            QString::from(format!("{err:#}")),
                        );
                    }
                }
            });
        });

        self.tasks.insert(task_id.clone(), task);
        QString::from(task_id)
    }

    fn cancel_task(&mut self, task_id: QString) {
        let task_id = task_id.to_string();
        if let Some(task) = self.tasks.remove(&task_id) {
            task.abort();
            info!("Cancelled app-store task {task_id}");
        }
    }

    fn sign_out(&mut self) {
        let Some(tool) = &self.ipa_tool else {
            eprintln!("IpaTool not initialized");
            return;
        };

        match tool.revoke() {
            Ok(()) => self.set_state(true, QString::default(), QString::default()),
            Err(err) => self.set_state(true, QString::default(), QString::from(format!("{}", err))),
        }
    }
}
