// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use crate::{RUNTIME, qt_threading::QtThreading};
use base64::{Engine as _, engine::general_purpose};
use idevice::springboardservices::SpringBoardServicesClient;
use macros::QtThreading;
use qmetaobject::prelude::*;
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(QObject, QtThreading)]
pub struct SpringBoardServices {
    base: qt_base_class!(trait QObject),
    springboard_client: Arc<Mutex<SpringBoardServicesClient>>,
    app_icon_loaded: qt_signal!(bundle_id: QString, icon_data: QString),
    fetch_app_icon: qt_method!(fn(bundle_id: QString)),
}

impl SpringBoardServices {
    pub fn new_with_sp_client(sp: SpringBoardServicesClient) -> Self {
        Self {
            springboard_client: Arc::new(Mutex::new(sp)),
            app_icon_loaded: Default::default(),
            fetch_app_icon: Default::default(),
            base: Default::default(),
        }
    }

    fn fetch_app_icon(&self, bundle_id: QString) {
        let qt_t = self.qt_thread();
        let bundle_id_owned = bundle_id.clone();
        let sb_client = self.springboard_client.clone();

        RUNTIME.spawn(async move {
            let mut sb = sb_client.lock().await;
            match sb.get_icon_pngdata(bundle_id_owned.to_string()).await {
                Ok(icon_data) => {
                    qt_t.queue(move |t| {
                        let icon_base64_string = general_purpose::STANDARD.encode(&icon_data);
                        t.app_icon_loaded(
                            bundle_id_owned,
                            QString::from(format!("data:image/png;base64,{}", icon_base64_string)),
                        );
                    });
                }
                Err(e) => {
                    eprintln!(
                        "fetch_app_icon: Failed to fetch app icon for bundle ID {}: {e}",
                        bundle_id_owned
                    );
                }
            };
        });
    }
}
