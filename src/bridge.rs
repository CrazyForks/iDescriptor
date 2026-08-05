// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use crate::{APP_DEVICE_STATE, run_sync};
use idevice::afc::AfcClient;
use idevice::afc::opcode::AfcFopenMode;
use std::io::SeekFrom;
use tokio::io::{AsyncReadExt, AsyncSeekExt};

pub struct AfcReader {
    udid: String,
    path: String,
}

impl AfcReader {
    pub fn new(udid: String, path: String) -> Self {
        Self { udid, path }
    }
    pub fn read_at(&self, offset: i64, size: i32) -> Vec<u8> {
        if size <= 0 || offset < 0 {
            return Vec::new();
        }

        let udid = self.udid.clone();
        let path = self.path.clone();
        // FIXME: is run_sync safe in this context?
        run_sync(async move {
            let maybe_device = APP_DEVICE_STATE.lock().await.get(udid.as_str()).cloned();

            let device = match maybe_device {
                Some(d) => d,
                None => {
                    eprintln!("read_at: device {} not found", udid);
                    return Vec::new();
                }
            };

            let mut afc = device.afc.lock().await;

            let mut fd = match afc.open(path.clone(), AfcFopenMode::RdOnly).await {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("read_at: open({}) failed: {}", path, e);
                    return Vec::new();
                }
            };

            if offset > 0 {
                if let Err(e) = fd.seek(SeekFrom::Start(offset as u64)).await {
                    eprintln!("read_at: seek({}, {}) failed: {}", path, offset, e);
                    let _ = fd.close().await;
                    return Vec::new();
                }
            }

            let mut buf = vec![0u8; size as usize];
            let n = match fd.read(&mut buf).await {
                Ok(n) => n,
                Err(e) => {
                    eprintln!("read_at: read({}, {}) failed: {}", path, offset, e);
                    let _ = fd.close().await;
                    return Vec::new();
                }
            };
            buf.truncate(n);
            let _ = fd.close().await;
            buf
        })
    }
}

#[cxx_qt::bridge]
pub mod bridge {

    extern "Rust" {
        type AfcReader;

        fn read_at(self: &AfcReader, offset: i64, size: i32) -> Vec<u8>;
    }

    unsafe extern "C++" {
        include!("bridge.h");

        include!("cxx-qt-lib/qimage.h");
        include!("cxx-qt-lib/qstring.h");

        type QImage = cxx_qt_lib::QImage;
        type QByteArray = cxx_qt_lib::QByteArray;
        type QString = cxx_qt_lib::QString;

        fn generate_thumbnail_with_reader(
            reader: &AfcReader,
            file_size: i32,
            requested_w: i32,
            requested_h: i32,
        ) -> QImage;

        fn heic_to_image(data: &[u8]) -> QImage;

        // fn qinput_get_text(ok: bool) -> QString;
    }
}
