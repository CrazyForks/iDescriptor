use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert, settings_manager};
use anyhow::{Context, anyhow};
use chrono::Local;
use image::{DynamicImage, ImageFormat, Luma};
use log::warn;
use macros::QtThreading;
use qmetaobject::prelude::*;
use qrcode::{EcLevel, QrCode};
use qttypes::{QByteArray, QStringList, QVariantMap};
use serde_json::json;
use std::{
    io::Cursor,
    net::{Ipv4Addr, SocketAddrV4},
    path::{Path, PathBuf},
    sync::Arc,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::{JoinHandle, JoinSet};

const MAX_PORT_ATTEMPTS: u16 = 10;
const QR_MAX_SIZE: u32 = 200;

#[derive(Clone)]
struct ImportServerContext {
    files: Arc<Vec<PathBuf>>,
    local_ip: String,
    port: u16,
    manifest_name: String,
}

#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct WebWirelessGalleryImport {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),
    download_progress: qt_signal!(file_name: QString, bytes_downloaded: i64, total_bytes: i64),
    qrCodeReady: qt_signal!(data: QByteArray, pixel_size: i32),
    start: qt_method!(fn(&mut self, files: QStringList)),
    stop: qt_method!(fn(&mut self)),
    server_task: Option<JoinHandle<()>>,
}

impl WebWirelessGalleryImport {
    pub fn new_with_state() -> Self {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", false);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "importUrl", QString::default());
        qvariantmap_insert!(state, "serverAddress", QString::default());
        qvariantmap_insert!(state, "qrCodeReady", false);

        let mut def = Self::default();
        def.state = state;
        def
    }

    fn start(&mut self, files: QStringList) {
        // Clear the previous listener and QR state before validating or
        // starting a replacement server.
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

        let start_port = settings_manager::wireless_file_server_port();
        let (listener, port) = match bind_listener(start_port) {
            Ok(bound) => bound,
            Err(err) => {
                self.set_error(&format!("Failed to start server: {err}"));
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

        let local_ip = local_ip();
        let manifest_name = manifest_file_name();
        let import_url = format!(
            "https://idescriptor.github.io/import?local={local_ip}&port={port}&file={manifest_name}"
        );
        let server_address = format!("{local_ip}:{port}");

        let (qr_code, qr_size) = match generate_qr_code(&import_url) {
            Ok(generated) => generated,
            Err(err) => {
                self.set_error(&format!("Failed to generate QR code: {err}"));
                return;
            }
        };

        let q_thread = self.qt_thread();
        let progress_thread = q_thread.clone();
        let context = ImportServerContext {
            files: Arc::new(selected_files),
            local_ip,
            port,
            manifest_name,
        };

        self.server_task = Some(RUNTIME.spawn(async move {
            let mut connections = JoinSet::new();
            loop {
                match listener.accept().await {
                    Ok((socket, _)) => {
                        let context = context.clone();
                        let q_thread = progress_thread.clone();
                        connections.spawn(async move {
                            handle_connection(socket, context, q_thread).await;
                        });
                        while connections.try_join_next().is_some() {}
                    }
                    Err(err) => {
                        warn!("Wireless gallery import accept failed: {err}");
                        break;
                    }
                }
            }
        }));

        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", true);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "importUrl", QString::from(import_url.clone()));
        qvariantmap_insert!(state, "serverAddress", QString::from(server_address));
        qvariantmap_insert!(state, "qrCodeReady", true);

        self.state = state;
        self.state_changed();
        self.qrCodeReady(QByteArray::from(qr_code.as_slice()), qr_size as i32);
    }

    fn stop(&mut self) {
        self.stop_server();

        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", false);
        qvariantmap_insert!(state, "error", QString::default());
        qvariantmap_insert!(state, "importUrl", QString::default());
        qvariantmap_insert!(state, "serverAddress", QString::default());
        qvariantmap_insert!(state, "qrCodeReady", false);

        self.state = state;
        self.state_changed();
    }

    fn set_error(&mut self, error: &str) {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", false);
        qvariantmap_insert!(state, "error", QString::from(error));
        qvariantmap_insert!(state, "importUrl", QString::default());
        qvariantmap_insert!(state, "serverAddress", QString::default());
        qvariantmap_insert!(state, "qrCodeReady", false);

        self.state = state;
        self.state_changed();
    }

    fn stop_server(&mut self) {
        if let Some(task) = self.server_task.take() {
            task.abort();
            // `abort` schedules cancellation. Waiting for the task here makes
            // sure its listener (and JoinSet of connections) are dropped
            // before a subsequent start attempts to bind the configured port.
            let _ = RUNTIME.block_on(task);
        }
    }
}

impl Drop for WebWirelessGalleryImport {
    fn drop(&mut self) {
        self.stop_server();
    }
}

async fn handle_connection(
    mut socket: TcpStream,
    context: ImportServerContext,
    q_thread: crate::qt_threading::QtThread<WebWirelessGalleryImport>,
) {
    let mut buffer = vec![0u8; 4096];
    let n = match socket.read(&mut buffer).await {
        Ok(n) if n > 0 => n,
        _ => return,
    };

    let request = String::from_utf8_lossy(&buffer[..n]);
    let mut parts = request
        .lines()
        .next()
        .unwrap_or_default()
        .split_whitespace();
    let method = parts.next().unwrap_or_default();
    let raw_path = parts.next().unwrap_or("/");

    if method != "GET" {
        write_response(
            &mut socket,
            "405 Method Not Allowed",
            "text/plain",
            b"Method Not Allowed",
        )
        .await;
        return;
    }

    let path = raw_path.split('?').next().unwrap_or(raw_path);
    if path == format!("/{}", context.manifest_name) {
        let body = manifest_json(&context);
        write_response(&mut socket, "200 OK", "application/json", body.as_bytes()).await;
        return;
    }

    if let Some(encoded_name) = path.strip_prefix("/serve/") {
        if let Some(file) = find_file_by_encoded_name(&context.files, encoded_name) {
            serve_file(&mut socket, file, q_thread).await;
            return;
        }
    }

    write_response(
        &mut socket,
        "404 Not Found",
        "text/html",
        b"<html><body><h1>404 Not Found</h1><p>The requested file was not found.</p></body></html>",
    )
    .await;
}

fn manifest_json(context: &ImportServerContext) -> String {
    let items: Vec<_> = context
        .files
        .iter()
        .map(|path| {
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("media");
            json!({
                "path": format!(
                    "http://{}:{}/serve/{}",
                    context.local_ip,
                    context.port,
                    urlencoding::encode(name),
                )
            })
        })
        .collect();

    json!({ "items": items }).to_string()
}

fn find_file_by_encoded_name(files: &[PathBuf], encoded_name: &str) -> Option<PathBuf> {
    let file_name = urlencoding::decode(encoded_name).ok()?;
    files
        .iter()
        .find(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name == file_name)
        })
        .cloned()
}

async fn serve_file(
    socket: &mut TcpStream,
    path: PathBuf,
    q_thread: crate::qt_threading::QtThread<WebWirelessGalleryImport>,
) {
    let metadata = match tokio::fs::metadata(&path).await {
        Ok(metadata) => metadata,
        Err(_) => {
            write_response(socket, "404 Not Found", "text/plain", b"File not found").await;
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

    if socket.write_all(headers.as_bytes()).await.is_err() {
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

async fn write_response(socket: &mut TcpStream, status: &str, content_type: &str, body: &[u8]) {
    let headers = format!(
        "HTTP/1.1 {status}\r\nContent-Length: {}\r\nContent-Type: {content_type}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = socket.write_all(headers.as_bytes()).await;
    let _ = socket.write_all(body).await;
}

fn bind_listener(start_port: u16) -> anyhow::Result<(std::net::TcpListener, u16)> {
    let end_port = start_port.saturating_add(MAX_PORT_ATTEMPTS);
    let mut last_error = None;

    for port in start_port..=end_port {
        let address = SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, port);
        match std::net::TcpListener::bind(address) {
            Ok(listener) => return Ok((listener, port)),
            Err(error) => last_error = Some(error),
        }
    }

    Err(anyhow!(
        "could not bind to any port between {start_port}-{end_port}: {}",
        last_error
            .map(|error| error.to_string())
            .unwrap_or_else(|| "unknown error".to_string())
    ))
}

fn manifest_file_name() -> String {
    format!(
        "{}-idescriptor-import.json",
        Local::now().format("%Y%m%d-%H%M%S")
    )
}

fn local_ip() -> String {
    local_ip_address::local_ip()
        .ok()
        .filter(std::net::IpAddr::is_ipv4)
        .map(|ip| ip.to_string())
        .unwrap_or_else(|| "127.0.0.1".to_string())
}

fn generate_qr_code(url: &str) -> anyhow::Result<(Vec<u8>, u32)> {
    let code = QrCode::with_error_correction_level(url.as_bytes(), EcLevel::M)
        .context("URL is too large to encode")?;
    let image = code
        .render::<Luma<u8>>()
        .max_dimensions(QR_MAX_SIZE, QR_MAX_SIZE)
        .build();
    let pixel_size = image.width();
    let mut png = Cursor::new(Vec::new());
    DynamicImage::ImageLuma8(image)
        .write_to(&mut png, ImageFormat::Png)
        .context("failed to encode QR code as PNG")?;
    Ok((png.into_inner(), pixel_size))
}

fn mime_type(path: &Path) -> &'static str {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_matches_the_shortcut_contract() {
        let context = ImportServerContext {
            files: Arc::new(vec![
                PathBuf::from("/tmp/photo one.jpg"),
                PathBuf::from("/tmp/über.mov"),
            ]),
            local_ip: "192.168.1.20".to_string(),
            port: 8080,
            manifest_name: "test-idescriptor-import.json".to_string(),
        };

        let manifest: serde_json::Value = serde_json::from_str(&manifest_json(&context)).unwrap();

        assert_eq!(
            manifest,
            json!({
                "items": [
                    { "path": "http://192.168.1.20:8080/serve/photo%20one.jpg" },
                    { "path": "http://192.168.1.20:8080/serve/%C3%BCber.mov" }
                ]
            })
        );
    }

    #[test]
    fn encoded_file_lookup_preserves_first_match_behavior() {
        let files = vec![
            PathBuf::from("/first/photo one.jpg"),
            PathBuf::from("/second/photo one.jpg"),
        ];

        assert_eq!(
            find_file_by_encoded_name(&files, "photo%20one.jpg"),
            Some(files[0].clone())
        );
        assert_eq!(find_file_by_encoded_name(&files, "missing.jpg"), None);
    }

    #[test]
    fn manifest_name_uses_the_original_timestamp_format() {
        let name = manifest_file_name();
        let timestamp = name.strip_suffix("-idescriptor-import.json").unwrap();

        assert!(chrono::NaiveDateTime::parse_from_str(timestamp, "%Y%m%d-%H%M%S").is_ok());
    }

    #[test]
    fn configured_port_falls_forward_when_occupied() {
        let occupied = std::net::TcpListener::bind((Ipv4Addr::UNSPECIFIED, 0)).unwrap();
        let start_port = occupied.local_addr().unwrap().port();
        if start_port == u16::MAX {
            return;
        }

        let (_listener, selected_port) = bind_listener(start_port).unwrap();

        assert!(selected_port > start_port);
        assert!(selected_port <= start_port.saturating_add(MAX_PORT_ATTEMPTS));
    }

    #[test]
    fn qr_code_is_a_bounded_png_with_a_quiet_zone() {
        let url = "https://idescriptor.github.io/import?local=192.168.1.20&port=8080&file=20260101-120000-idescriptor-import.json";
        let code = QrCode::with_error_correction_level(url.as_bytes(), EcLevel::M).unwrap();
        let (png, pixel_size) = generate_qr_code(url).unwrap();
        let image = image::load_from_memory_with_format(&png, ImageFormat::Png)
            .unwrap()
            .to_luma8();
        let modules_with_quiet_zone = code.width() as u32 + 8;
        let module_size = pixel_size / modules_with_quiet_zone;

        assert!(pixel_size <= QR_MAX_SIZE);
        assert_eq!(image.width(), pixel_size);
        assert_eq!(image.height(), pixel_size);
        assert_eq!(pixel_size % modules_with_quiet_zone, 0);
        assert!(module_size > 0);
        assert!(
            image
                .rows()
                .take((module_size * 4) as usize)
                .flatten()
                .all(|pixel| pixel.0[0] == u8::MAX)
        );
        assert!(image.pixels().any(|pixel| pixel.0[0] == 0));

        for y in 0..code.width() {
            for x in 0..code.width() {
                let sample_x = (x as u32 + 4) * module_size + module_size / 2;
                let sample_y = (y as u32 + 4) * module_size + module_size / 2;
                let expected = match code[(x, y)] {
                    qrcode::Color::Dark => 0,
                    qrcode::Color::Light => u8::MAX,
                };
                assert_eq!(image.get_pixel(sample_x, sample_y).0[0], expected);
            }
        }
    }
}
