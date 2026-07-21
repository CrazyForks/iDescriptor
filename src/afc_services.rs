use crate::device_ctx;
use crate::media_streamer::MediaStreamSession;
use crate::qt_threading::QtThreading;
use crate::{RUNTIME, run_sync};
use idevice::afc::AfcClient;
use log::{debug, error, info, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantMap};
use std::sync::Arc;
use tokio::sync::Mutex;
#[derive(QObject, QtThreading)]
pub struct AfcServices {
    base: qt_base_class!(trait QObject),
    afc: Arc<Mutex<AfcClient>>,
    udid: String,
    // file_to_buffer: qt_method!(fn(self, file_path: QString) -> QByteArray),
    // get_file_size: qt_method!(fn(self, path: QString) -> i64),
    check_is_dir_and_list: qt_method!(fn(&self, path: QString)),

    check_is_dir_and_list_finished: qt_signal!(
        success: bool,
        entries: QVariantMap
    ),
    start_video_stream: qt_method!(fn(&self, file_path: QString) -> QString),
    release_video_stream: qt_method!(fn(&self, url: QString)),
    delete_path: qt_method!(fn(&self, path: QString) -> bool),
    //only required for hause_arrest afc
    bundle_id: qt_property!(QString),
}

impl AfcServices {
    pub fn from_afc_client(
        afc_client: Arc<Mutex<AfcClient>>,
        /* udid is for debugging purposes */
        udid: String,
        //only required for hause_arrest afc
        bundle_id: Option<String>,
    ) -> Self {
        Self {
            afc: afc_client,
            udid: udid,
            base: Default::default(),
            // list_dir: Default::default(),
            // file_to_buffer: Default::default(),
            // is_directory: Default::default(),
            // get_file_size: Default::default(),
            check_is_dir_and_list: Default::default(),
            check_is_dir_and_list_finished: Default::default(),
            start_video_stream: Default::default(),
            release_video_stream: Default::default(),
            delete_path: Default::default(),
            bundle_id: bundle_id.map_or_else(QString::default, QString::from),
        }
    }

    // FIXME: resolve symlinks
    fn check_is_dir_and_list(&self, path: QString) {
        let path_str = path.to_string();
        let afc_arc = self.afc.clone();
        let qt_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            let mut map = QVariantMap::default();
            let mut afc = afc_arc.lock().await;
            let success = match afc.list_dir(&path_str).await {
                Ok(list) => {
                    for name in list {
                        // ui already has up/down buttons maybe unnecessary
                        if name == "." || name == ".." {
                            continue;
                        }
                        let full_path = format!("{}/{}", path_str, name);
                        let is_dir = match afc.get_file_info(&full_path).await {
                            Ok(info) => info.st_ifmt == "S_IFDIR",
                            Err(e) => {
                                eprintln!("Failed to get file info for {full_path}: {e}");
                                false
                            }
                        };
                        map.insert(QString::from(name), QVariant::from(&is_dir));
                    }
                    true
                }
                Err(e) => {
                    eprintln!("Failed to read directory {path_str}: {e}");
                    false
                }
            };

            qt_thread.queue(move |q| {
                q.check_is_dir_and_list_finished(success, map);
            });
        });
    }

    // fn file_to_buffer(&self, album_path: QString) -> QByteArray {
    //     let udid = self.get_udid().to_string();
    //     let album_path_string = album_path.to_string();

    //     let data: Vec<u8> = run_sync(async move {
    //         let afc_arc = {
    //             let maybe_device = APP_DEVICE_STATE.lock().await.get(udid.as_str()).cloned();

    //             let device = match maybe_device {
    //                 Some(d) => d,
    //                 None => {
    //                     eprintln!("file_to_buffer: device {udid} not found");
    //                     return Vec::new();
    //                 }
    //             };
    //             device.afc.clone()
    //         };

    //         let mut afc = afc_arc.lock().await;

    //         let mut fd = match afc
    //             .open(album_path_string.clone(), AfcFopenMode::RdOnly)
    //             .await
    //         {
    //             Ok(f) => f,
    //             Err(e) => {
    //                 eprintln!("file_to_buffer: failed to open {album_path_string}: {e}");
    //                 return Vec::new();
    //             }
    //         };

    //         let mut buf = Vec::new();
    //         let mut chunk = vec![0u8; 8192];

    //         loop {
    //             let n = match fd.read(&mut chunk).await {
    //                 Ok(n) => n,
    //                 Err(e) => {
    //                     eprintln!("file_to_buffer: failed to read {album_path_string}: {e}");
    //                     buf.clear();
    //                     break;
    //                 }
    //             };
    //             if n == 0 {
    //                 break;
    //             }
    //             buf.extend_from_slice(&chunk[..n]);
    //         }
    //         fd.close().await.ok();
    //         buf
    //     });

    //     if data.is_empty() {
    //         QByteArray::default()
    //     } else {
    //         QByteArray::from(&data[..])
    //     }
    // }

    // fn get_file_size(self: &Self, path: QString) -> i64 {
    //     let udid = self.get_udid().to_string();
    //     let path_string = path.to_string();

    //     run_sync(async move {
    //         let afc_arc = {
    //             let maybe_device = APP_DEVICE_STATE.lock().await.get(udid.as_str()).cloned();

    //             let device = match maybe_device {
    //                 Some(d) => d,
    //                 None => {
    //                     eprintln!("file_to_buffer: device {udid} not found");
    //                     return -1;
    //                 }
    //             };
    //             device.afc.clone()
    //         };

    //         let mut afc = afc_arc.lock().await;

    //         afc::get_file_size(&mut afc, path_string)
    //             .await
    //             .map(|v| v as i64)
    //             .unwrap_or(-1)
    //     })
    // }

    // fn get_dirs_item_count(self: &Self, dirs: QList<QString>) -> i64 {
    //     let udid = self.get_udid().to_string();

    //     let mut dir_vec: Vec<String> = Vec::new();
    //     for i in 0..dirs.len() {
    //         if let Some(qdir) = dirs.get(i) {
    //             dir_vec.push(qdir.to_string());
    //         }
    //     }

    //     run_sync(async move {
    //         let afc_arc = {
    //             let maybe_device = APP_DEVICE_STATE.lock().await.get(udid.as_str()).cloned();

    //             let device = match maybe_device {
    //                 Some(d) => d,
    //                 None => {
    //                     eprintln!("get_dirs_item_count: device {udid} not found");
    //                     return -1;
    //                 }
    //             };

    //             device.afc.clone()
    //         };

    //         let mut afc = afc_arc.lock().await;
    //         let mut total: i64 = 0;

    //         for dir_str in dir_vec {
    //             let names = match afc.list_dir(&dir_str).await {
    //                 Ok(list) => list,
    //                 Err(e) => {
    //                     eprintln!("get_dirs_item_count: list_dir({dir_str}) failed: {e}");
    //                     continue;
    //                 }
    //             };

    //             let count = names
    //                 .into_iter()
    //                 .filter(|name| name != "." && name != "..")
    //                 .count() as i64;

    //             total += count;
    //         }

    //         total
    //     })
    // }

    fn list_files_flat(&self, dir: QString) -> QStringList {
        let dir_str = dir.to_string();
        let afc_arc = self.afc.clone();
        let entries = run_sync(async move {
            let mut afc = afc_arc.lock().await;
            let names = match afc.list_dir(&dir_str).await {
                Ok(list) => list,
                Err(e) => {
                    eprintln!("list_files_flat: list_dir({dir_str}) failed: {e}");
                    return Vec::new();
                }
            };

            let mut files = Vec::new();
            for name in names {
                if name == "." || name == ".." {
                    continue;
                }
                let full_path = format!("{}/{}", dir_str, name);

                match afc.get_file_info(full_path.clone()).await {
                    Ok(info) => {
                        if info.st_ifmt != "S_IFDIR" {
                            files.push(full_path);
                        }
                    }
                    Err(e) => {
                        eprintln!("list_files_flat: get_file_info({full_path}) failed: {e}");
                        continue;
                    }
                }
            }
            files
        });

        let mut qlist: QStringList = QStringList::default();
        for path in entries {
            qlist.push(QString::from(path));
        }
        qlist
    }

    fn start_video_stream(&self, file_path: QString) -> QString {
        let path_str = file_path.to_string();
        let afc = self.afc.clone();
        let udid = self.udid.clone();
        let stream_udid = udid.clone();

        info!("Starting media stream for udid={udid} path={path_str}");
        let result: anyhow::Result<String> = run_sync(async move {
            let device = device_ctx::get_device(&stream_udid).await?;
            let (url, session) = MediaStreamSession::start(afc, path_str).await?;
            device
                .video_streams
                .lock()
                .await
                .insert(url.clone(), session);
            Ok(url)
        });

        match result {
            Ok(url) => {
                info!("Serving media stream at {url} for udid={udid}");
                QString::from(url)
            }
            Err(err) => {
                error!("Failed to start media stream for udid={udid}: {err}");
                QString::default()
            }
        }
    }

    fn release_video_stream(&self, url: QString) {
        let udid = self.udid.clone();
        let url_str = url.to_string();

        if url_str.is_empty() {
            return;
        }

        RUNTIME.spawn(async move {
            let Some(device) = device_ctx::get_device_opt(&udid).await else {
                eprintln!("release_video_stream: device {udid} not found");
                return;
            };

            let session = {
                let mut video_streams = device.video_streams.lock().await;
                video_streams.remove(&url_str)
            };

            if let Some(mut session) = session {
                info!("Shutting down media stream {url_str}");
                session.shutdown().await;
            } else {
                warn!("No active media stream for {url_str}");
            }
        });
    }

    fn delete_path(&self, path: QString) -> bool {
        let path_str = path.to_string();
        let afc_arc = self.afc.clone();

        run_sync(async move {
            let mut afc = afc_arc.lock().await;

            match afc.remove(&path_str).await {
                Ok(_) => true,
                Err(e) => {
                    eprintln!("delete_path: delete({path_str}) failed: {e}");
                    false
                }
            }
        })
    }
}

impl Drop for AfcServices {
    fn drop(&mut self) {
        debug!("AfcServices dropped for udid: {}", self.udid);
    }
}
