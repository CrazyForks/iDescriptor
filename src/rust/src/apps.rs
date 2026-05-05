use crate::RUNTIME;

use crate::qmap_insert;
use cxx_qt::Threading;
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};
use ipatool::Account;
use ipatool::IpaTool;
use std::pin::Pin;

#[cxx_qt::bridge]
mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        include!("cxx-qt-lib/qmap.h");
        include!("cxx-qt-lib/qstring.h");

        type QString = cxx_qt_lib::QString;
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QMap_QString_QVariant, state)]
        type Apps = super::RApps;

        #[qinvokable]
        fn init(self: Pin<&mut Apps>);

        #[qinvokable]
        fn sign_in(self: Pin<&mut Apps>, email: &QString, password: &QString);
    }
    impl cxx_qt::Threading for Apps {}
}
pub struct RApps {
    state: QMap<QMapPair_QString_QVariant>,
}

impl Default for RApps {
    fn default() -> Self {
        let mut state = QMap::<QMapPair_QString_QVariant>::default();
        qmap_insert!(state, "init", false);
        qmap_insert!(state, "error", QString::default());
        qmap_insert!(state, "email", QString::default());
        Self { state }
    }
}

impl qobject::Apps {
    fn init(self: Pin<&mut Self>) {
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

                    let mut state = QMap::<QMapPair_QString_QVariant>::default();
                    qmap_insert!(state, "init", true);
                    qmap_insert!(state, "error", QString::default());
                    qmap_insert!(state, "email", QString::from(acc.email));

                    q_thread.queue(|t| t.set_state(state)).ok();
                }
                Err(err) => {
                    let mut state = QMap::<QMapPair_QString_QVariant>::default();
                    qmap_insert!(state, "init", true);
                    qmap_insert!(state, "error", QString::from(format!("{}", err)));
                    qmap_insert!(state, "email", QString::default());

                    q_thread.queue(|t| t.set_state(state)).ok();
                }
            }
        });
    }

    fn sign_in(self: Pin<&mut Self>, email: &QString, password: &QString) {
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
