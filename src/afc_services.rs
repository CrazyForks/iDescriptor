use crate::device_ctx;
use crate::qt_threading::QtThreading;
use crate::{RUNTIME, run_sync};
use idevice::{
    afc::{AfcClient, opcode::AfcFopenMode},
};
use macros::QtThreading;
use once_cell::sync::Lazy;
use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantMap};
use regex::Regex;
use std::cmp::min;
use std::{any::type_name, sync::Arc};
use std::{collections::HashMap, net::IpAddr};
use std::{io::SeekFrom, pin::Pin};
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt, BufWriter};
use tokio::net::TcpListener;
use tokio::sync::Mutex;
use tokio::sync::oneshot;
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
            match afc.list_dir(&path_str).await {
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
                }
                Err(e) => {
                    eprintln!("Failed to read directory {path_str}: {e}");
                }
            };

            qt_thread.queue(move |q| {
                q.check_is_dir_and_list_finished(true, map);
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
        let cloned_path = path_str.clone();
        let afc = self.afc.clone();
        let udid = self.udid.clone();

        eprintln!(
            "start_video_stream: request udid={} path={}",
            &udid, cloned_path
        );

        // bind ephemeral port on localhost
        let listener = match std::net::TcpListener::bind("127.0.0.1:0") {
            Ok(l) => l,
            Err(e) => {
                eprintln!("start_video_stream: bind failed: {e}");
                return QString::default();
            }
        };
        let local_addr = match listener.local_addr() {
            Ok(a) => a,
            Err(e) => {
                eprintln!("start_video_stream: local_addr failed: {e}");
                return QString::default();
            }
        };
        listener.set_nonblocking(true).ok();

        // create Tokio TcpListener inside runtime
        let std_listener = {
            let _guard = RUNTIME.handle().enter();
            match TcpListener::from_std(listener) {
                Ok(l) => l,
                Err(e) => {
                    eprintln!("start_video_stream: from_std failed: {e}");
                    return QString::default();
                }
            }
        };

        let port = local_addr.port();

        let encoded = urlencoding::encode(&cloned_path);
        let url = format!("http://127.0.0.1:{}/{}", port, encoded);
        let url_clone = url.clone();
        let url_clone_for_log = url.clone();
        let (shutdown_tx, mut shutdown_rx) = oneshot::channel::<()>();
        let url_for_insert = url.clone();
        let udid_for_insert = udid.clone();
        // FIXME: should we do it here ?
        let inserted = run_sync(async move {
            let maybe_device = device_ctx::get_device_opt(udid_for_insert).await;
            let device = match maybe_device {
                Some(d) => d,
                None => return false,
            };

            let mut video_streams = device.video_streams.lock().await;
            video_streams.insert(url_for_insert, shutdown_tx);
            true
        });
        if !inserted {
            eprintln!(
                "start_video_stream: failed to insert video stream for udid={} path={}",
                &udid, cloned_path
            );
            return QString::default();
        }

        eprintln!(
            "start_video_stream: serving {} for udid={} path={}",
            url_clone, udid, cloned_path
        );
        // accept-loop task
        RUNTIME.spawn(async move {
            loop {
                tokio::select! {
                    _ = &mut shutdown_rx => {
                        // shutdown requested
                        eprintln!("start_video_stream: shutdown requested for {}", url_clone);
                        break;
                    }
                    accept_res = std_listener.accept() => {
                        let (socket, peer) = match accept_res {
                            Ok(s) => s,
                            Err(e) => {
                                eprintln!("start_video_stream: accept error: {e} on {}", url_clone);
                                break;
                            }
                        };
                        eprintln!("start_video_stream: accepted connection from {} on {}", peer, url_clone);

                        let path_clone = path_str.clone();
                        let afc_clone = afc.clone();

                        tokio::spawn(async move {
                            Self::handle_http_connection(afc_clone, path_clone, socket).await;
                        });
                    }
                }
            }
            eprintln!("start_video_stream: accept-loop exiting for udid : {} with url :{}", udid, url_clone);
        });

        QString::from(url_clone_for_log)
    }

    fn delete_path(&self, path: QString) -> bool {
        let udid = self.udid.clone();
        let path_str = path.to_string();

        run_sync(async move {
            let afc_arc = {
                let maybe_device = device_ctx::get_device_opt(&udid).await;

                let device = match maybe_device {
                    Some(d) => d,
                    None => {
                        eprintln!("delete_path: device {udid} not found");
                        return false;
                    }
                };

                device.afc.clone()
            };

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

    async fn handle_http_connection(
        afc: Arc<Mutex<AfcClient>>,
        path: String,
        mut socket: tokio::net::TcpStream,
    ) {
        let mut afc = afc.lock().await;
        let mut buf = vec![0u8; 4096];
        let n = match socket.read(&mut buf).await {
            Ok(n) if n > 0 => n,
            _ => {
                eprintln!(
                    "handle_http_connection: failed to read initial request for {}",
                    path
                );
                return;
            }
        };

        let req_str = String::from_utf8_lossy(&buf[..n]).to_string();
        eprintln!(
            "handle_http_connection: received request head for {}: {}",
            path,
            req_str.lines().take(10).collect::<Vec<_>>().join("\\n")
        );
        let lines: Vec<&str> = req_str.split("\r\n").collect();
        if lines.is_empty() {
            eprintln!("handle_http_connection: empty request lines for {}", path);
            let _ = socket.shutdown().await;
            return;
        }

        // request line: "GET /... HTTP/1.1"
        let mut method = "GET".to_string();
        if let Some(first) = lines.first() {
            let parts: Vec<&str> = first.split_whitespace().collect();
            if parts.len() >= 1 {
                method = parts[0].to_string();
            }
        }
        eprintln!("handle_http_connection: method={} for {}", method, path);

        if method != "GET" && method != "HEAD" {
            eprintln!(
                "handle_http_connection: unsupported method {} for {}",
                method, path
            );
            //FIXME:FLUSH?
            let _ = socket
                .write_all(
                    b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                )
                .await;
            let _ = socket.shutdown().await;
            return;
        }

        // parse Range header
        let mut has_range = false;
        let mut range_start: i64 = 0;
        let mut range_end: i64 = -1;
        for line in &lines[1..] {
            if line.is_empty() {
                break;
            }
            if let Some(rest) = line
                .strip_prefix("Range: bytes=")
                .or_else(|| line.strip_prefix("range: bytes="))
            {
                let parts: Vec<&str> = rest.trim().split('-').collect();
                if parts.len() == 2 {
                    has_range = true;
                    if let Ok(s) = parts[0].trim().parse::<i64>() {
                        range_start = s;
                    }
                    if !parts[1].trim().is_empty() {
                        if let Ok(e) = parts[1].trim().parse::<i64>() {
                            range_end = e;
                        }
                    }
                }
            }
        }
        eprintln!(
            "handle_http_connection: range parsed has_range={} start={} end={} for {}",
            has_range, range_start, range_end, path
        );

        let file_size = {
            let info = match afc.get_file_info(path.clone()).await {
                Ok(i) => i,
                Err(e) => {
                    eprintln!(
                        "handle_http_connection: get_file_info({}) failed: {}",
                        path, e
                    );
                    let _ = socket
                        .write_all(
                            b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        )
                        .await;
                    let _ = socket.shutdown().await;
                    return;
                }
            };
            info.size as i64
        };

        eprintln!(
            "handle_http_connection: file_size={} for {}",
            file_size, path
        );
        if file_size <= 0 {
            eprintln!("handle_http_connection: invalid file_size for {}", path);
            let _ = socket
                .write_all(
                    b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                )
                .await;
            let _ = socket.shutdown().await;
            return;
        }

        let mut start = 0_i64;
        let mut end = file_size - 1;

        if has_range {
            if range_start >= 0 {
                start = range_start;
            }
            if range_end >= 0 && range_end < file_size {
                end = range_end;
            }
            if start < 0 || start >= file_size || start > end {
                eprintln!(
                    "handle_http_connection: range not satisfiable for {} (start={}, end={}, file_size={})",
                    path, start, end, file_size
                );
                let _ = socket
                    .write_all(
                        b"HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                    )
                    .await;
                let _ = socket.shutdown().await;
                return;
            }
        }

        let content_len = (end - start + 1).max(0) as u64;
        let path_lower = path.to_lowercase();
        let mime_type = if path_lower.ends_with(".mp4") || path_lower.ends_with(".m4v") {
            "video/mp4"
        } else if path_lower.ends_with(".mov") {
            "video/quicktime"
        } else if path_lower.ends_with(".avi") {
            "video/x-msvideo"
        } else if path_lower.ends_with(".mkv") {
            "video/x-matroska"
        } else {
            "application/octet-stream"
        };

        let mut headers = String::new();
        if has_range {
            headers.push_str("HTTP/1.1 206 Partial Content\r\n");
            headers.push_str(&format!(
                "Content-Range: bytes {}-{}/{}\r\n",
                start, end, file_size
            ));
        } else {
            headers.push_str("HTTP/1.1 200 OK\r\n");
        }

        headers.push_str(&format!("Content-Length: {}\r\n", content_len));
        headers.push_str("Accept-Ranges: bytes\r\n");
        headers.push_str(&format!("Content-Type: {}\r\n", mime_type));
        headers.push_str("Connection: close\r\n");
        headers.push_str("Cache-Control: no-cache\r\n\r\n");

        eprintln!(
            "handle_http_connection: sending headers for {}: {}",
            path,
            headers.lines().next().unwrap_or_default()
        );
        if socket.write_all(headers.as_bytes()).await.is_err() {
            eprintln!("handle_http_connection: write headers failed for {}", path);
            let _ = socket.shutdown().await;
            return;
        }
        if socket.flush().await.is_err() {
            eprintln!(
                "handle_http_connection: flush failed after headers for {}",
                path
            );
            let _ = socket.shutdown().await;
            return;
        }

        if method == "HEAD" {
            eprintln!(
                "handle_http_connection: HEAD request completed for {}",
                path
            );
            let _ = socket.shutdown().await;
            return;
        }

        let mut fd = match afc.open(path.clone(), AfcFopenMode::RdOnly).await {
            Ok(f) => f,
            Err(e) => {
                eprintln!("handle_http_connection: open({}) failed: {}", path, e);
                let _ = socket.shutdown().await;
                return;
            }
        };

        if start > 0 {
            if let Err(e) = fd.seek(SeekFrom::Start(start as u64)).await {
                eprintln!(
                    "handle_http_connection: seek({}, {}) failed: {}",
                    path, start, e
                );
                let _ = fd.close().await;
                let _ = socket.shutdown().await;
                return;
            }
        }

        eprintln!(
            "handle_http_connection: streaming {} bytes ({}-{}) for {}",
            content_len, start, end, path
        );

        let mut remaining = content_len;
        // let mut chunk = vec![0u8; 64 * 1024];
        let mut writer = BufWriter::with_capacity(256 * 1024, &mut socket);
        let mut chunk = vec![0u8; 256 * 1024];

        while remaining > 0 {
            let to_read = min(chunk.len() as u64, remaining) as usize;
            let n = match fd.read(&mut chunk[..to_read]).await {
                Ok(n) => n,
                Err(e) => {
                    eprintln!("handle_http_connection: read({}) failed: {}", path, e);
                    break;
                }
            };
            if n == 0 {
                eprintln!("handle_http_connection: EOF while streaming {}", path);
                break;
            }
            if let Err(e) = writer.write_all(&chunk[..n]).await {
                eprintln!("handle_http_connection: write({}) failed: {}", path, e);
                break;
            }
            remaining -= n as u64;
        }

        writer.flush().await.ok();
        //drop(writer) is explicit so the borrow is released before we touch socket again.
        drop(writer);

        let _ = fd.close().await;
        let _ = socket.shutdown().await;
        eprintln!(
            "handle_http_connection: finished/closed connection for {}",
            path
        );
    }
}
