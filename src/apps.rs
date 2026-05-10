use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use ipatool::Account;
use ipatool::IpaTool;
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantMap};
use std::pin::Pin;

#[derive(QObject, Default, QtThreading)]
pub struct Apps {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY  state_changed),
    state_changed: qt_signal!(),

    init: qt_method!(fn(&mut self)),
    sign_in: qt_method!(fn(&mut self, email: QString, password: QString)),
}

impl Apps {
    pub fn new_with_state() -> Self {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "init", false);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "email", QString::default());

        let mut def = Self::default();
        def.state = state;
        def
    }

    fn init(&mut self) {
        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            let res: anyhow::Result<Option<ipatool::Account>> = async {
                let tool = IpaTool::new_default().await?;
                Ok(tool.account_info().await?)
            }
            .await;

            match res {
                Ok(maybe_acc) => {
                    let acc = maybe_acc.unwrap_or_default();
                    println!("email :{}", acc.email);

                    let mut state = QVariantMap::default();
                    qvariantmap_insert!(state, "init", true);
                    qvariantmap_insert!(state, "error", QString::default());
                    qvariantmap_insert!(state, "email", QString::from(acc.email));

                    q_thread.queue(|t| {
                        t.state = state;
                        t.state_changed();
                    })
                }
                Err(err) => {
                    let mut state = QVariantMap::default();
                    qvariantmap_insert!(state, "init", true);
                    qvariantmap_insert!(state, "error", QString::from(format!("{}", err)));
                    qvariantmap_insert!(state, "email", QString::default());

                    q_thread.queue(|t| {
                        t.state = state;
                        t.state_changed();
                    });
                }
            }
        });
    }

    fn sign_in(&mut self, email: QString, password: QString) {
        // FIXME: implement
        // RUNTIME.spawn(async move {
        //     let res: anyhow::Result<()> = async {
        //         let tool = IpaTool::new_default().await?;

        //         let auth_code_cb: Box<dyn Fn() -> ipatool::Result<String> + Send + Sync> =
        //             Box::new(|| {
        //             });
        //         tool.login(
        //             &email.to_string(),
        //             &password.to_string(),
        //             Some(auth_code_cb),
        //             None,
        //         )
        //         .await;

        //         Ok(())
        //     }
        //     .await;

        //     Ok(())
        // });
    }
}
