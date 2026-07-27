use axum::{
    Router,
    body::{Body, Bytes},
    extract::State,
    http::{HeaderMap, HeaderValue, Method, Response, StatusCode, header},
    routing::any,
};
use futures::stream;
use http_range_header::parse_range_header;
use idevice::afc::{AfcClient, opcode::AfcFopenMode};
use log::{debug, error, warn};
use std::{io, io::SeekFrom, ops::RangeInclusive, sync::Arc};
use tokio::{
    io::{AsyncReadExt, AsyncSeekExt},
    net::TcpListener,
    sync::{Mutex, mpsc},
    task::JoinHandle,
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::RUNTIME;

const STREAM_CHUNK_SIZE: usize = 256 * 1024;
const STREAM_CHANNEL_CAPACITY: usize = 2;

#[derive(Clone)]
struct MediaStreamState {
    afc: Arc<Mutex<AfcClient>>,
    path: Arc<str>,
    file_size: u64,
    mime_type: &'static str,
    cancellation: CancellationToken,
    producers: TaskTracker,
}

/// Owns one preview window's HTTP endpoint and all response producers spawned by it.
/// Individual AFC file descriptors remain request-scoped so seeking and looping can
/// open a fresh descriptor while this session stays alive.
pub struct MediaStreamSession {
    cancellation: CancellationToken,
    server_task: Option<JoinHandle<()>>,
}

impl MediaStreamSession {
    // TODO: expose the URL programmatically localhost:$PORT/idescriptor/media/$VIDEOPATH
    pub async fn start(afc: Arc<Mutex<AfcClient>>, path: String) -> anyhow::Result<(String, Self)> {
        let file_size = {
            let mut afc = afc.lock().await;
            afc.get_file_info(path.clone()).await?.size as u64
        };
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let local_addr = listener.local_addr()?;
        let cancellation = CancellationToken::new();
        let producers = TaskTracker::new();
        let state = Arc::new(MediaStreamState {
            afc,
            file_size,
            mime_type: mime_type_for_path(&path),
            path: Arc::from(path),
            cancellation: cancellation.clone(),
            producers: producers.clone(),
        });

        let app = Router::new()
            .route("/media", any(handle_media_request))
            .with_state(state);
        let server_cancellation = cancellation.clone();
        let cleanup_cancellation = cancellation.clone();
        let server_task = RUNTIME.spawn(async move {
            let result = axum::serve(listener, app)
                .with_graceful_shutdown(server_cancellation.cancelled_owned())
                .await;
            if let Err(err) = result {
                error!("Media stream server failed: {err}");
            }

            // Also stop producers if the listener exits unexpectedly.
            cleanup_cancellation.cancel();
            producers.close();
            producers.wait().await;
            debug!("Media stream server and producers stopped");
        });

        let url = format!("http://127.0.0.1:{}/media", local_addr.port());
        Ok((
            url,
            Self {
                cancellation,
                server_task: Some(server_task),
            },
        ))
    }

    pub async fn shutdown(&mut self) {
        self.cancellation.cancel();
        if let Some(server_task) = self.server_task.take() {
            if let Err(err) = server_task.await {
                warn!("Media stream server task failed during shutdown: {err}");
            }
        }
    }
}

impl Drop for MediaStreamSession {
    fn drop(&mut self) {
        // Drop cannot await the server task. Explicit shutdown remains responsible
        // for draining producers; cancellation is the safety net for lost sessions.
        self.cancellation.cancel();
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum RangeDecision {
    Full,
    Partial(RangeInclusive<u64>),
}

fn resolve_range(value: Option<&HeaderValue>, file_size: u64) -> Result<RangeDecision, ()> {
    let Some(value) = value else {
        return Ok(RangeDecision::Full);
    };
    if file_size == 0 {
        return Err(());
    }

    let ranges = parse_range_header(value.to_str().map_err(|_| ())?)
        .map_err(|_| ())?
        .validate(file_size)
        .map_err(|_| ())?;

    // Qt Multimedia sends single ranges. HTTP allows a server to ignore a
    // multi-range request, so serve the complete representation instead.
    if ranges.len() != 1 {
        return Ok(RangeDecision::Full);
    }

    Ok(RangeDecision::Partial(ranges[0].clone()))
}

async fn handle_media_request(
    State(state): State<Arc<MediaStreamState>>,
    method: Method,
    headers: HeaderMap,
) -> Response<Body> {
    if method != Method::GET && method != Method::HEAD {
        return empty_response(
            StatusCode::METHOD_NOT_ALLOWED,
            Some((header::ALLOW, "GET, HEAD")),
        );
    }
    if state.cancellation.is_cancelled() {
        return empty_response(StatusCode::SERVICE_UNAVAILABLE, None);
    }

    let file_size = state.file_size;

    let range = match resolve_range(headers.get(header::RANGE), file_size) {
        Ok(range) => range,
        Err(()) => return range_not_satisfiable(file_size),
    };
    let (status, start, end) = match range {
        RangeDecision::Full => (StatusCode::OK, 0, file_size.saturating_sub(1)),
        RangeDecision::Partial(range) => {
            (StatusCode::PARTIAL_CONTENT, *range.start(), *range.end())
        }
    };
    let content_length = if file_size == 0 { 0 } else { end - start + 1 };

    let body = if method == Method::HEAD || content_length == 0 {
        Body::empty()
    } else {
        start_body_producer(state.clone(), start, content_length)
    };

    let mut response = Response::builder()
        .status(status)
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::CONTENT_TYPE, state.mime_type)
        .header(header::CONTENT_LENGTH, content_length.to_string())
        .header(header::CONNECTION, "close")
        .header(header::CACHE_CONTROL, "no-cache")
        .body(body)
        .expect("static media response headers must be valid");

    if status == StatusCode::PARTIAL_CONTENT {
        let value = format!("bytes {start}-{end}/{file_size}");
        response.headers_mut().insert(
            header::CONTENT_RANGE,
            HeaderValue::from_str(&value).expect("numeric Content-Range must be valid"),
        );
    }
    response
}

fn start_body_producer(state: Arc<MediaStreamState>, start: u64, content_length: u64) -> Body {
    let (body_tx, body_rx) = mpsc::channel(STREAM_CHANNEL_CAPACITY);
    let producer_state = state.clone();

    state.producers.spawn(async move {
        produce_range(producer_state, start, content_length, body_tx).await;
    });

    let body_stream = stream::unfold(body_rx, |mut receiver| async move {
        receiver.recv().await.map(|item| (item, receiver))
    });
    Body::from_stream(body_stream)
}

async fn produce_range(
    state: Arc<MediaStreamState>,
    start: u64,
    content_length: u64,
    body_tx: mpsc::Sender<Result<Bytes, io::Error>>,
) {
    let mut afc = tokio::select! {
        _ = state.cancellation.cancelled() => {
            return;
        }
        afc = state.afc.clone().lock_owned() => afc,
    };

    // Do not cancel an in-flight AFC protocol operation. Cancellation is checked
    // between complete operations so the shared AFC connection remains usable.
    let mut fd = match afc.open(state.path.to_string(), AfcFopenMode::RdOnly).await {
        Ok(fd) => fd,
        Err(err) => {
            let message = format!("Media file open failed for {}: {err}", state.path);
            warn!("{message}");
            let _ = body_tx.try_send(Err(io::Error::other(message)));
            return;
        }
    };

    if start > 0 {
        if let Err(err) = fd.seek(SeekFrom::Start(start)).await {
            let message = format!(
                "Media file seek failed for {} at {start}: {err}",
                state.path
            );
            warn!("{message}");
            let _ = body_tx.try_send(Err(io::Error::other(message)));
            if let Err(close_err) = fd.close().await {
                warn!("Failed to close AFC descriptor after seek error: {close_err}");
            }
            return;
        }
    }

    if state.cancellation.is_cancelled() {
        if let Err(err) = fd.close().await {
            warn!("Failed to close cancelled AFC descriptor: {err}");
        }
        return;
    }

    let mut remaining = content_length;
    let mut buffer = vec![0_u8; STREAM_CHUNK_SIZE];
    while remaining > 0 && !state.cancellation.is_cancelled() {
        let to_read = remaining.min(buffer.len() as u64) as usize;
        let read = match fd.read(&mut buffer[..to_read]).await {
            Ok(0) => break,
            Ok(read) => read,
            Err(err) => {
                let message = format!("AFC read failed for {}: {err}", state.path);
                error!("{message}");
                // Error reporting must not delay descriptor cleanup when the HTTP
                // consumer has stopped polling a full response channel.
                let _ = body_tx.try_send(Err(io::Error::other(message)));
                break;
            }
        };

        let bytes = Bytes::copy_from_slice(&buffer[..read]);
        let sent = tokio::select! {
            _ = state.cancellation.cancelled() => false,
            result = body_tx.send(Ok(bytes)) => result.is_ok(),
        };
        if !sent {
            break;
        }
        remaining -= read as u64;
    }

    if let Err(err) = fd.close().await {
        warn!(
            "Failed to close AFC media descriptor for {}: {err}",
            state.path
        );
    }
}

fn empty_response(
    status: StatusCode,
    header_value: Option<(header::HeaderName, &'static str)>,
) -> Response<Body> {
    let mut response = Response::builder().status(status);
    if let Some((name, value)) = header_value {
        response = response.header(name, value);
    }
    response
        .header(header::CONTENT_LENGTH, "0")
        .body(Body::empty())
        .expect("static empty response headers must be valid")
}

fn range_not_satisfiable(file_size: u64) -> Response<Body> {
    Response::builder()
        .status(StatusCode::RANGE_NOT_SATISFIABLE)
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::CONTENT_RANGE, format!("bytes */{file_size}"))
        .header(header::CONTENT_LENGTH, "0")
        .body(Body::empty())
        .expect("numeric range response headers must be valid")
}

fn mime_type_for_path(path: &str) -> &'static str {
    let path = path.to_ascii_lowercase();
    if path.ends_with(".mp4") || path.ends_with(".m4v") {
        "video/mp4"
    } else if path.ends_with(".mov") {
        "video/quicktime"
    } else if path.ends_with(".avi") {
        "video/x-msvideo"
    } else if path.ends_with(".mkv") {
        "video/x-matroska"
    } else if path.ends_with(".webm") {
        "video/webm"
    } else if path.ends_with(".3gp") {
        "video/3gpp"
    } else {
        "application/octet-stream"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header(value: &'static str) -> HeaderValue {
        HeaderValue::from_static(value)
    }

    #[test]
    fn resolves_missing_range_as_full_response() {
        assert_eq!(resolve_range(None, 100), Ok(RangeDecision::Full));
    }

    #[test]
    fn resolves_bounded_range() {
        assert_eq!(
            resolve_range(Some(&header("bytes=10-19")), 100),
            Ok(RangeDecision::Partial(10..=19))
        );
    }

    #[test]
    fn resolves_open_ended_range() {
        assert_eq!(
            resolve_range(Some(&header("bytes=90-")), 100),
            Ok(RangeDecision::Partial(90..=99))
        );
    }

    #[test]
    fn preserves_large_open_ended_range() {
        assert_eq!(
            resolve_range(Some(&header("bytes=1024-")), 10 * 1024 * 1024),
            Ok(RangeDecision::Partial(1024..=(10 * 1024 * 1024 - 1)))
        );
    }

    #[test]
    fn preserves_explicit_bounded_range() {
        assert_eq!(
            resolve_range(Some(&header("bytes=0-2097151")), 10 * 1024 * 1024),
            Ok(RangeDecision::Partial(0..=2_097_151))
        );
    }

    #[test]
    fn resolves_suffix_range() {
        assert_eq!(
            resolve_range(Some(&header("bytes=-10")), 100),
            Ok(RangeDecision::Partial(90..=99))
        );
    }

    #[test]
    fn truncates_oversized_range() {
        assert_eq!(
            resolve_range(Some(&header("bytes=90-200")), 100),
            Ok(RangeDecision::Partial(90..=99))
        );
    }

    #[test]
    fn rejects_malformed_and_unsatisfiable_ranges() {
        assert_eq!(resolve_range(Some(&header("not-a-range")), 100), Err(()));
        assert_eq!(resolve_range(Some(&header("bytes=100-200")), 100), Err(()));
    }

    #[test]
    fn ignores_multiple_ranges() {
        assert_eq!(
            resolve_range(Some(&header("bytes=0-9,20-29")), 100),
            Ok(RangeDecision::Full)
        );
    }

    #[test]
    fn range_error_response_advertises_complete_size() {
        let response = range_not_satisfiable(100);
        assert_eq!(response.status(), StatusCode::RANGE_NOT_SATISFIABLE);
        assert_eq!(response.headers()[header::ACCEPT_RANGES], "bytes");
        assert_eq!(response.headers()[header::CONTENT_RANGE], "bytes */100");
        assert_eq!(response.headers()[header::CONTENT_LENGTH], "0");
    }

    #[test]
    fn method_error_response_advertises_allowed_methods() {
        let response = empty_response(
            StatusCode::METHOD_NOT_ALLOWED,
            Some((header::ALLOW, "GET, HEAD")),
        );
        assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(response.headers()[header::ALLOW], "GET, HEAD");
        assert_eq!(response.headers()[header::CONTENT_LENGTH], "0");
    }

    #[test]
    fn detects_supported_video_mime_types() {
        assert_eq!(mime_type_for_path("/DCIM/example.MP4"), "video/mp4");
        assert_eq!(mime_type_for_path("/DCIM/example.mov"), "video/quicktime");
        assert_eq!(mime_type_for_path("/DCIM/example.webm"), "video/webm");
        assert_eq!(
            mime_type_for_path("/DCIM/example.bin"),
            "application/octet-stream"
        );
    }
}
