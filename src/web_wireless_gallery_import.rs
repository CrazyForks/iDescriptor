use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantMap};
use serde_json::json;
use std::path::PathBuf;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::oneshot;

#[derive(QObject, Default, QtThreading)]
pub struct WebWirelessGalleryImport {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),
    download_progress: qt_signal!(file_name: QString, bytes_downloaded: i64, total_bytes: i64),
    start: qt_method!(fn(&mut self, files: QStringList)),
    stop: qt_method!(fn(&mut self)),
    shutdown: Option<oneshot::Sender<()>>,
}

impl WebWirelessGalleryImport {
    pub fn new_with_state() -> Self {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", false);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "importUrl", QString::default());
        qvariantmap_insert!(state, "serverAddress", QString::default());

        let mut def = Self::default();
        def.state = state;
        def
    }

    fn start(&mut self, files: QStringList) {
        self.stop();

        let selected_files: Vec<PathBuf> = files
            .into_iter()
            .map(|file| PathBuf::from(file.to_string()))
            .filter(|path| path.is_file())
            .collect();

        if selected_files.is_empty() {
            self.set_error("No gallery-compatible files selected.");
            return;
        }

        let listener = match std::net::TcpListener::bind("0.0.0.0:0") {
            Ok(listener) => listener,
            Err(err) => {
                self.set_error(&format!("Failed to start server: {err}"));
                return;
            }
        };

        let port = match listener.local_addr() {
            Ok(addr) => addr.port(),
            Err(err) => {
                self.set_error(&format!("Failed to read server address: {err}"));
                return;
            }
        };

        if let Err(err) = listener.set_nonblocking(true) {
            self.set_error(&format!("Failed to configure server: {err}"));
            return;
        }

        let listener = {
            let _guard = RUNTIME.handle().enter();
            match TcpListener::from_std(listener) {
                Ok(listener) => listener,
                Err(err) => {
                    self.set_error(&format!("Failed to start server: {err}"));
                    return;
                }
            }
        };

        let local_ip = local_ip().unwrap_or_else(|| "127.0.0.1".to_string());
        let manifest_name = "manifest.json";
        let import_url = format!(
            "https://idescriptor.github.io/import?local={local_ip}&port={port}&file={manifest_name}"
        );
        let server_address = format!("{local_ip}:{port}");

        let (shutdown_tx, mut shutdown_rx) = oneshot::channel::<()>();
        self.shutdown = Some(shutdown_tx);

        let q_thread = self.qt_thread();
        let progress_thread = q_thread.clone();

        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", true);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "importUrl", QString::from(import_url));
        qvariantmap_insert!(state, "serverAddress", QString::from(server_address));

        self.state = state;
        self.state_changed();

        RUNTIME.spawn(async move {
            loop {
                tokio::select! {
                    _ = &mut shutdown_rx => break,
                    accept = listener.accept() => {
                        match accept {
                            Ok((socket, _)) => {
                                let files = selected_files.clone();
                                let q_thread = progress_thread.clone();
                                tokio::spawn(async move {
                                    handle_connection(socket, files, q_thread).await;
                                });
                            }
                            Err(err) => {
                                eprintln!("wireless import accept error: {err}");
                                break;
                            }
                        }
                    }
                }
            }
        });
    }

    fn stop(&mut self) {
        if let Some(shutdown) = self.shutdown.take() {
            let _ = shutdown.send(());
        }

        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", false);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "importUrl", QString::default());
        qvariantmap_insert!(state, "serverAddress", QString::default());

        self.state = state;
        self.state_changed();
    }

    fn set_error(&mut self, error: &str) {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", false);
        qvariantmap_insert!(state, "error", QString::from(error));
        qvariantmap_insert!(state, "importUrl", QString::default());
        qvariantmap_insert!(state, "serverAddress", QString::default());

        self.state = state;
        self.state_changed();
    }
}

impl Drop for WebWirelessGalleryImport {
    fn drop(&mut self) {
        if let Some(shutdown) = self.shutdown.take() {
            let _ = shutdown.send(());
        }
    }
}

async fn handle_connection(
    mut socket: TcpStream,
    files: Vec<PathBuf>,
    q_thread: crate::qt_threading::QtThread<WebWirelessGalleryImport>,
) {
    let mut buffer = vec![0u8; 4096];
    let n = match socket.read(&mut buffer).await {
        Ok(n) if n > 0 => n,
        _ => return,
    };

    let request = String::from_utf8_lossy(&buffer[..n]);
    let host = request
        .lines()
        .find_map(|line| {
            line.strip_prefix("Host: ")
                .or_else(|| line.strip_prefix("host: "))
        })
        .unwrap_or_default()
        .trim()
        .to_string();
    let mut parts = request
        .lines()
        .next()
        .unwrap_or_default()
        .split_whitespace();
    let method = parts.next().unwrap_or_default();
    let raw_path = parts.next().unwrap_or("/");

    if method != "GET" && method != "HEAD" {
        write_response(
            &mut socket,
            "405 Method Not Allowed",
            "text/plain",
            b"",
            method,
        )
        .await;
        return;
    }

    let path = raw_path.split('?').next().unwrap_or(raw_path);
    if path == "/" || path == "/manifest.json" {
        let body = manifest_json(&files, &host);
        write_response(
            &mut socket,
            "200 OK",
            "application/json; charset=utf-8",
            body.as_bytes(),
            method,
        )
        .await;
        return;
    }

    if let Some(rest) = path.strip_prefix("/file/") {
        let mut parts = rest.split('/');
        let index = parts
            .next()
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(usize::MAX);

        if let Some(file) = files.get(index) {
            serve_file(&mut socket, file.clone(), method, q_thread).await;
            return;
        }
    }

    write_response(&mut socket, "404 Not Found", "text/plain", b"", method).await;
}

fn manifest_json(files: &[PathBuf], host: &str) -> String {
    let entries: Vec<_> = files
        .iter()
        .enumerate()
        .map(|(index, path)| {
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("media");
            let size = std::fs::metadata(path)
                .map(|metadata| metadata.len())
                .unwrap_or(0);
            let relative_url = format!("/file/{}/{}", index, urlencoding::encode(name));
            let absolute_url = if host.is_empty() {
                relative_url.clone()
            } else {
                format!("http://{host}{relative_url}")
            };
            json!({
                "name": name,
                "fileName": name,
                "url": absolute_url,
                "relativeUrl": relative_url,
                "size": size,
                "mimeType": mime_type(path),
            })
        })
        .collect();

    json!({
        "files": entries,
        "items": entries,
    })
    .to_string()
}

async fn serve_file(
    socket: &mut TcpStream,
    path: PathBuf,
    method: &str,
    q_thread: crate::qt_threading::QtThread<WebWirelessGalleryImport>,
) {
    let metadata = match tokio::fs::metadata(&path).await {
        Ok(metadata) => metadata,
        Err(_) => {
            write_response(socket, "404 Not Found", "text/plain", b"", method).await;
            return;
        }
    };

    let total = metadata.len();
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("media")
        .to_string();

    let headers = format!(
        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        total,
        mime_type(&path)
    );

    if socket.write_all(headers.as_bytes()).await.is_err() || method == "HEAD" {
        return;
    }

    let mut file = match tokio::fs::File::open(&path).await {
        Ok(file) => file,
        Err(_) => return,
    };

    let mut sent = 0u64;
    let mut chunk = vec![0u8; 128 * 1024];
    loop {
        let n = match file.read(&mut chunk).await {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => break,
        };

        if socket.write_all(&chunk[..n]).await.is_err() {
            break;
        }

        sent += n as u64;
        let file_name = file_name.clone();
        q_thread.queue(move |q| {
            q.download_progress(QString::from(file_name), sent as i64, total as i64);
        });
    }
}

async fn write_response(
    socket: &mut TcpStream,
    status: &str,
    content_type: &str,
    body: &[u8],
    method: &str,
) {
    let headers = format!(
        "HTTP/1.1 {status}\r\nContent-Length: {}\r\nContent-Type: {content_type}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = socket.write_all(headers.as_bytes()).await;
    if method != "HEAD" {
        let _ = socket.write_all(body).await;
    }
}

fn local_ip() -> Option<String> {
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    Some(socket.local_addr().ok()?.ip().to_string())
}

fn mime_type(path: &PathBuf) -> &'static str {
    match path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "bmp" => "image/bmp",
        "tiff" | "tif" => "image/tiff",
        "webp" => "image/webp",
        "heic" => "image/heic",
        "heif" => "image/heif",
        "mp4" | "m4v" => "video/mp4",
        "mov" => "video/quicktime",
        "avi" => "video/x-msvideo",
        "mkv" => "video/x-matroska",
        "3gp" => "video/3gpp",
        "webm" => "video/webm",
        _ => "application/octet-stream",
    }
}
