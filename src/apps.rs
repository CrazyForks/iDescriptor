use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use ipatool::error::IpaToolError;
use ipatool::IpaTool;
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::QVariantMap;
use std::sync::{
    mpsc::{self, SyncSender},
    Arc,
};
use ::log::{debug};

enum AuthCodeResponse {
    Code(String),
    Cancelled,
}

#[derive(QObject, Default, QtThreading)]
pub struct Apps {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY  state_changed),
    state_changed: qt_signal!(),
    ipa_tool: Option<Arc<IpaTool>>,
    sign_in_busy: bool,
    pending_auth_code: Option<(String, SyncSender<AuthCodeResponse>)>,
    init: qt_method!(fn(&mut self)),
    sign_in: qt_method!(fn(&mut self, email: QString, password: QString)),
    auth_code_received: qt_method!(fn(&mut self, request_id: QString, code: QString)),
    auth_code_cancelled: qt_method!(fn(&mut self, request_id: QString)),
    sign_out: qt_method!(fn(&mut self)),
    search: qt_method!(fn(&mut self, term: QString)),
    authCodeRequested: qt_signal!(request_id: QString, email: QString),
    signInFinished: qt_signal!(success: bool, error: QString),
    search_ready: qt_signal!(search_term : QString, success: bool, res: QString),
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

    fn init(&mut self) {
        let tool = match IpaTool::new_default() {
            Ok(tool) => tool,
            Err(err) => {
                eprintln!("Error creating IpaTool: {}", err);
                self.set_state(true, QString::default(), QString::from(format!("{}", err)));
                return;
            }
        };
        match tool.account_info() {
            Ok(maybe_acc) => {
                let acc = maybe_acc.unwrap_or_default();

                self.set_state(true, QString::from(acc.email), QString::default());
            }
            Err(err) => {
                self.set_state(true, QString::default(), QString::from(format!("{}", err)));
            }
        };
        self.ipa_tool = Some(Arc::new(tool));
    }

    fn sign_in(&mut self, email: QString, password: QString) {
        if self.sign_in_busy {
            self.signInFinished(
                false,
                QString::from("Sign in is already in progress."),
            );
            return;
        }

        self.sign_in_busy = true;
        self.set_state(true, QString::default(), QString::default());

        let email_string = email.to_string();
        let password_string = password.to_string();
        let Some(tool) = self.ipa_tool.clone() else {
            self.sign_in_busy = false;
            self.set_state(true, QString::default(), QString::from("IpaTool not initialized"));
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
        self.set_state(true, QString::default(), QString::default());
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
        self.set_state(true, QString::default(), QString::default());
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

    fn sign_out(&mut self) {
        let Some(tool) = &self.ipa_tool else {
            eprintln!("IpaTool not initialized");
            return;
        };

        match tool.revoke() {
            Ok(()) => self.set_state(true, QString::default(), QString::default()),
            Err(err) => {
                self.set_state(true, QString::default(), QString::from(format!("{}", err)))
            }
        }
    }
}
