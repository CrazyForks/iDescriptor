use crate::{POSSIBLE_ROOT, run_sync};
use cpp::*;
use idevice::{
    IdeviceError, IdeviceService,
    afc::{AfcClient, opcode::AfcFopenMode},
    diagnostics_relay::DiagnosticsRelayClient,
    house_arrest::HouseArrestClient,
    installation_proxy::InstallationProxyClient,
    provider::IdeviceProvider,
};
use plist::Dictionary as PlistDictionary;
use plist_macro::plist;
use qmetaobject::prelude::*;
use qmetaobject::*;
use rusqlite::Connection;
use serde_json::json;
use std::ffi::c_void;
use std::io::SeekFrom;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio::sync::Mutex;

cpp! {{
    struct TraitObject2 { void *data; void *vtable; };
    #include <QCoreApplication>
    #include <QFileSystemWatcher>
    #include <QTimer>
    #include <QDirIterator>
    #include <QMap>
    #include <QDesktopServices>
    #include <QStandardPaths>
    #include <QBuffer>
    #include <QImage>
    #include <QGuiApplication>
    #include <QObject>
    #include <QClipboard>
    #include <QEvent>
    #include "src/include/bridge.h"
    #include <gst/gst.h>

    QCoreApplication *globalApp = nullptr;
}}

pub const PUBLIC_STAGING: &str = "PublicStaging";

pub async fn get_battery_info(diag: &mut DiagnosticsRelayClient) -> Option<PlistDictionary> {
    match diag.ioregistry(None, None, Some("IOPMPowerSource")).await {
        Ok(Some(dict)) => Some(dict),
        _ => None,
    }
}

pub async fn get_cable_info(diag: &mut DiagnosticsRelayClient) -> Option<PlistDictionary> {
    match diag
        .ioregistry(None, None, Some("AppleTriStarBuiltIn"))
        .await
    {
        Ok(Some(dict)) => Some(dict),
        _ => None,
    }
}

pub async fn detect_jailbroken(afc: &mut AfcClient) -> bool {
    match afc.list_dir(format!("{}/bin", POSSIBLE_ROOT)).await {
        Ok(vec) => vec.len() > 0,
        Err(_) => false,
    }
}

pub fn qstring_to_f64(qstring: QString) -> Result<f64, std::num::ParseFloatError> {
    let rust_string: String = qstring.into();
    rust_string.parse::<f64>()
}

pub async fn calculate_apps_usage(
    instproxy: &mut InstallationProxyClient,
) -> Result<u64, Box<dyn std::error::Error + Send + Sync>> {
    let options = plist!({
        "ApplicationType": "User",
        "ReturnAttributes": [
            "StaticDiskUsage",
            "DynamicDiskUsage"
        ]
    });
    let apps = instproxy.browse(Some(options)).await?;
    let mut total_apps_space = 0u64;

    for app_info in apps {
        if let Some(app_dict) = app_info.as_dictionary() {
            if let Some(static_usage) = app_dict
                .get("StaticDiskUsage")
                .and_then(|v| v.as_unsigned_integer())
            {
                total_apps_space += static_usage;
            }

            if let Some(dynamic_usage) = app_dict
                .get("DynamicDiskUsage")
                .and_then(|v| v.as_unsigned_integer())
            {
                total_apps_space += dynamic_usage;
            }
        }
    }

    Ok(total_apps_space)
}

pub async fn vend_app_documents(
    provider: &dyn IdeviceProvider,
    bundle_id: &str,
) -> Result<AfcClient, idevice::IdeviceError> {
    let house_arrest_client = HouseArrestClient::connect(provider).await?;
    let afc_client = house_arrest_client.vend_documents(bundle_id).await?;
    Ok(afc_client)
}

pub fn query_gallery_usage(db_bytes: &mut Vec<u8>) -> Result<u64, rusqlite::Error> {
    // HACK: WAL -> legacy mode patch
    if db_bytes.len() > 20 && db_bytes[18] == 0x02 {
        db_bytes[18] = 0x01;
        db_bytes[19] = 0x01;
    }
    println!("Querying gallery usage for disk usage calculation...");

    // Open in-memory DB
    let conn = Connection::open_in_memory()?;

    unsafe {
        let db_ptr = rusqlite::ffi::sqlite3_deserialize(
            conn.handle(),
            b"main\0".as_ptr() as *const std::os::raw::c_char,
            db_bytes.as_mut_ptr(),
            db_bytes.len() as i64,
            db_bytes.len() as i64,
            rusqlite::ffi::SQLITE_DESERIALIZE_READONLY as u32,
        );
        if db_ptr != rusqlite::ffi::SQLITE_OK {
            return Err(rusqlite::Error::SqliteFailure(
                rusqlite::ffi::Error::new(db_ptr),
                None,
            ));
        }
    }

    let size: i64 = conn.query_row(
        "SELECT COALESCE(SUM(ZORIGINALFILESIZE), 0) FROM ZADDITIONALASSETATTRIBUTES",
        [],
        |row| row.get(0),
    )?;

    println!("Gallery usage calculated: {} bytes", size);
    Ok(size as u64)
}

pub fn get_lockdown_path() -> PathBuf {
    if let Ok(val) = std::env::var("USBMUXD_PAIRING_FILES_LOCATION") {
        if !val.is_empty() {
            eprintln!("Pulling pairing files from USBMUXD_PAIRING_FILES_LOCATION: {val}");
            return PathBuf::from(val);
        }
    }

    #[cfg(target_os = "linux")]
    {
        PathBuf::from("/var/lib/lockdown")
    }

    #[cfg(target_os = "macos")]
    {
        PathBuf::from("/var/db/lockdown")
    }

    #[cfg(target_os = "windows")]
    {
        let base = std::env::var_os("PROGRAMDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"));
        base.join("Apple").join("Lockdown")
    }
}

/// Ensure `PublicStaging` exists on device via AFC
pub async fn ensure_public_staging(afc: &mut AfcClient) -> Result<(), IdeviceError> {
    // Try to stat and if it fails, create directory
    match afc.get_file_info(PUBLIC_STAGING).await {
        Ok(_) => Ok(()),
        Err(_) => afc.mk_dir(PUBLIC_STAGING).await,
    }
}

// converts album info to json
pub fn create_album_info(
    album_id: i32,
    item_count: i32,
    asset_dir: String,
    asset_file_name: String,
) -> String {
    json!({"album_id" : album_id, "item_count" : item_count,"file_path" : format!("{}/{}",asset_dir,asset_file_name)})
        .to_string()
}

use qttypes::QVariantMap;

pub fn qvariantmap_insert<T>(map: &mut QVariantMap, key: &str, value: &T)
where
    QVariant: for<'a> From<&'a T>,
{
    map.insert(QString::from(key), QVariant::from(value));
}

#[macro_export]
macro_rules! qvariantmap_insert {
    ($map:expr, $key:expr , $value:expr) => {
        $crate::utils::qvariantmap_insert(&mut $map, $key, &$value)
    };
}

pub fn is_video_file(path: &str) -> bool {
    let ext = path
        .rsplit_once('.')
        .map(|(_, e)| e.to_ascii_lowercase())
        .unwrap_or_default();

    matches!(
        ext.as_str(),
        "mp4"
            | "mov"
            | "m4v"
            | "avi"
            | "mkv"
            | "webm"
            | "flv"
            | "wmv"
            | "3gp"
            | "mpeg"
            | "mpg"
            | "ts"
            | "mts"
            | "m2ts"
    )
}

pub fn serde_json_to_qt_array(v: &serde_json::Value) -> QJsonArray {
    let mut ret = QJsonArray::default();
    if let Some(arr) = v.as_array() {
        for param in arr {
            match param {
                serde_json::Value::Number(v) => {
                    ret.push(QJsonValue::from(v.as_f64().unwrap()));
                }
                serde_json::Value::Bool(v) => {
                    ret.push(QJsonValue::from(*v));
                }
                serde_json::Value::String(v) => {
                    ret.push(QJsonValue::from(QString::from(v.clone())));
                }
                serde_json::Value::Array(v) => {
                    ret.push(QJsonValue::from(serde_json_to_qt_array(
                        &serde_json::Value::Array(v.to_vec()),
                    )));
                }
                serde_json::Value::Object(_) => {
                    ret.push(QJsonValue::from(serde_json_to_qt_object(param)));
                }
                serde_json::Value::Null => { /* ::log::warn!("null unimplemented");*/ }
            };
        }
    }
    ret
}
pub fn serde_json_to_qt_object(v: &serde_json::Value) -> QJsonObject {
    let mut map = QJsonObject::default();
    if let Some(obj) = v.as_object() {
        for (k, v) in obj {
            match v {
                serde_json::Value::Number(v) => {
                    map.insert(k, QJsonValue::from(v.as_f64().unwrap()));
                }
                serde_json::Value::Bool(v) => {
                    map.insert(k, QJsonValue::from(*v));
                }
                serde_json::Value::String(v) => {
                    map.insert(k, QJsonValue::from(QString::from(v.clone())));
                }
                serde_json::Value::Array(v) => {
                    map.insert(
                        k,
                        QJsonValue::from(serde_json_to_qt_array(&serde_json::Value::Array(
                            v.to_vec(),
                        ))),
                    );
                }
                serde_json::Value::Object(_) => {
                    map.insert(k, QJsonValue::from(serde_json_to_qt_object(v)));
                }
                serde_json::Value::Null => { /* ::log::warn!("null unimplemented");*/ }
            };
        }
    }
    map
}

pub fn create_image_from_buffer(buf: &[u8]) -> QImage {
    if buf.is_empty() {
        return QImage::default();
    }

    let buf_ptr = buf.as_ptr();
    let buf_len: i32 = buf.len().try_into().unwrap_or(i32::MAX);

    cpp!(unsafe [buf_ptr as "const uchar*", buf_len as "int"] -> QImage as "QImage" {
        return QImage::fromData(buf_ptr, buf_len, nullptr);
    })
}

pub fn qt_queued_callback<T: QObject + 'static, T2: Send + 'static, F: FnMut(&T, T2) + 'static>(
    qptr: QPointer<T>,
    mut cb: F,
) -> impl Fn(T2) + Send + Sync + Clone + 'static {
    qmetaobject::queued_callback(move |arg| {
        if let Some(this) = qptr.as_pinned() {
            let this = this.borrow();
            cb(this, arg);
        }
    })
}
pub fn qt_queued_callback_mut<
    T: QObject + 'static,
    T2: Send + 'static,
    F: FnMut(&mut T, T2) + 'static,
>(
    qptr: QPointer<T>,
    mut cb: F,
) -> impl Fn(T2) + Send + Sync + Clone + 'static {
    qmetaobject::queued_callback(move |arg| {
        if let Some(this) = qptr.as_pinned() {
            let mut this = this.borrow_mut();
            cb(&mut this, arg);
        }
    })
}

// pub fn catch_qt_file_open<F: FnMut(QUrl)>(cb: F) {
//     let func: Box<dyn FnMut(QUrl)> = Box::new(cb);
//     let cb_ptr = Box::into_raw(func);
//     cpp!(unsafe [cb_ptr as "TraitObject2"] {
//         qGuiApp->installEventFilter(new QtEventFilter([cb_ptr](QUrl url) {
//             rust!(Rust_catch_qt_file_open [cb_ptr: *mut dyn FnMut(QUrl) as "TraitObject2", url: QUrl as "QUrl"] {
//                 let mut cb = unsafe { Box::from_raw(cb_ptr) };
//                 cb(url.clone());
//                 let _ = Box::into_raw(cb); // leak again so it doesn't get deleted here
//             });
//         }));
//     });
// }

// pub fn get_data_location() -> String {
//     cpp!(unsafe [] -> QString as "QString" {
//         return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
//     })
//     .into()
// }

// pub fn install_crash_handler() -> std::io::Result<()> {
//     let cur_dir = std::env::current_dir()?;

//     #[cfg(not(any(target_os = "android", target_os = "ios")))]
//     {
//         let os_str = cur_dir.as_os_str();
//         let path: Vec<breakpad_sys::PathChar> = {
//             #[cfg(windows)]
//             {
//                 use std::os::windows::ffi::OsStrExt;
//                 os_str.encode_wide().collect()
//             }
//             #[cfg(unix)]
//             {
//                 use std::os::unix::ffi::OsStrExt;
//                 Vec::from(os_str.as_bytes())
//             }
//         };

//         unsafe {
//             extern "C" fn callback(
//                 path: *const breakpad_sys::PathChar,
//                 path_len: usize,
//                 _ctx: *mut c_void,
//             ) {
//                 let path_slice = unsafe { std::slice::from_raw_parts(path, path_len) };

//                 let path = {
//                     #[cfg(windows)]
//                     {
//                         use std::os::windows::ffi::OsStringExt;
//                         std::path::PathBuf::from(std::ffi::OsString::from_wide(path_slice))
//                     }
//                     #[cfg(unix)]
//                     {
//                         use std::os::unix::ffi::OsStrExt;
//                         std::path::PathBuf::from(std::ffi::OsStr::from_bytes(path_slice).to_owned())
//                     }
//                 };

//                 println!("Crashdump written to {}", path.display());
//             }

//             breakpad_sys::attach_exception_handler(
//                 path.as_ptr(),
//                 path.len(),
//                 callback,
//                 std::ptr::null_mut(),
//                 breakpad_sys::INSTALL_BOTH_HANDLERS,
//             );
//         }
//     }

//     // Upload crash dumps
//     crate::core::run_threaded(move || {
//         if let Ok(files) = std::fs::read_dir(cur_dir) {
//             for path in files.flatten() {
//                 let path = path.path();
//                 if path.to_string_lossy().ends_with(".dmp") {
//                     if let Ok(content) = std::fs::read(&path) {
//                         if let Ok(Ok(body)) = ureq::post("https://api.gyroflow.xyz/upload_dump")
//                             .header("Content-Type", "application/octet-stream")
//                             .send(&content)
//                             .map(|x| x.into_body().read_to_string())
//                         {
//                             ::log::debug!("Minidump uploaded: {}", body.as_str());
//                             let _ = std::fs::remove_file(path);
//                         }
//                     }
//                 }
//             }
//         }
//     });
//     Ok(())
// }

pub fn tr(context: &str, text: &str) -> String {
    let context = QString::from(context);
    let text = QString::from(text);
    cpp!(unsafe [context as "QString", text as "QString"] -> QString as "QString" {
        return QCoreApplication::translate(qUtf8Printable(context), qUtf8Printable(text));
    })
    .to_string()
}

pub fn get_version() -> String {
    let ver = env!("CARGO_PKG_VERSION");
    if option_env!("GITHUB_REF").map_or(false, |x| x.contains("tags")) {
        ver.to_string() // Official, tagged version
    } else if let Some(gh_run) = option_env!("GITHUB_RUN_NUMBER") {
        format!("{} (gh{})", ver, gh_run)
    } else if let Some(time) = option_env!("BUILD_TIME") {
        format!("{} (dev{})", ver, time)
    } else {
        ver.to_string()
    }
}

pub fn copy_to_clipboard(text: QString) {
    cpp!(unsafe [text as "QString"] { QGuiApplication::clipboard()->setText(text); })
}

pub fn image_data_to_base64(w: u32, h: u32, s: u32, data: &[u8]) -> QString {
    let ptr = data.as_ptr();
    cpp!(unsafe [w as "uint32_t", h as "uint32_t", s as "uint32_t", ptr as "const uint8_t *"] -> QString as "QString" {
        QImage img(ptr, w, h, s, QImage::Format_RGBA8888_Premultiplied);
        QByteArray byteArray;
        QBuffer buffer(&byteArray);
        buffer.open(QIODevice::WriteOnly);
        img.save(&buffer, "JPEG", 50);
        QString b64("data:image/jpg;base64,");
        b64.append(QString::fromLatin1(byteArray.toBase64().data()));
        return b64;
    })
}

pub fn image_to_b64(img: QImage) -> QString {
    cpp!(unsafe [img as "QImage"] -> QString as "QString" {
        QByteArray byteArray;
        QBuffer buffer(&byteArray);
        buffer.open(QIODevice::WriteOnly);
        img.save(&buffer, "JPEG", 50);
        QString b64("data:image/jpg;base64,");
        b64.append(QString::fromLatin1(byteArray.toBase64().data()));
        return b64;
    })
}

pub struct AfcReader {
    udid: String,
    path: String,
    afc_arc: Arc<Mutex<AfcClient>>,
}

impl AfcReader {
    pub fn new(udid: String, path: String, afc_arc: Arc<Mutex<AfcClient>>) -> Self {
        Self {
            udid,
            path,
            afc_arc,
        }
    }

    pub async fn get_size(&self) -> i32 {
        let mut afc = self.afc_arc.lock().await;

        match afc.get_file_info(self.path.clone()).await {
            Ok(info) => info.size as i32,
            Err(_) => 0,
        }
    }

    pub fn read_at(&self, offset: i64, size: i32) -> Vec<u8> {
        if size <= 0 || offset < 0 {
            return Vec::new();
        }

        let udid = self.udid.clone();
        let path = self.path.clone();
        let afc_arc = self.afc_arc.clone();
        // FIXME: is run_sync safe in this context?
        run_sync(async move {
            let mut afc = afc_arc.lock().await;

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

#[unsafe(no_mangle)]
pub extern "C" fn afc_reader_read_at(
    reader_ptr: *const c_void,
    offset: i64,
    size: i32,
    out_buf: *mut u8,
    out_len: *mut i32,
) {
    let reader = unsafe { &*(reader_ptr as *const AfcReader) };
    let data = reader.read_at(offset, size);
    let n = data.len().min(size as usize);
    unsafe {
        std::ptr::copy_nonoverlapping(data.as_ptr(), out_buf, n);
        *out_len = n as i32;
    }
}

pub fn generate_thumbnail(
    reader: &AfcReader,
    file_size: i32,
    requested_w: i32,
    requested_h: i32,
) -> QImage {
    let reader_ptr = reader as *const AfcReader as *const c_void;

    cpp!(unsafe [
        reader_ptr  as "const void*",
        file_size   as "int32_t",
        requested_w as "int32_t",
        requested_h as "int32_t"
    ] -> QImage as "QImage" {
        return generate_thumbnail_with_reader_ffi(
            reader_ptr, file_size, requested_w, requested_h
        );
    })
}

pub fn empty_qjsvalue() -> QJSValue {
    cpp!(unsafe [] -> QJSValue as "QJSValue" { return QJSValue(); })
}

pub fn engine_ptr_new_object(engine_ptr: *mut c_void, obj_ptr: *mut c_void) -> QJSValue {
    cpp!(unsafe [
        engine_ptr as "QQmlEngine *",
        obj_ptr as "QObject *"
    ] -> QJSValue as "QJSValue" {
        return engine_ptr->newQObject(obj_ptr);
    })
}
//TODO: implement
// pub fn heic_to_qimage()

pub fn force_load_gst_gl() -> bool {
    /*
    need to load qml6glsink in order
    to make Qt6GLVideoItem available on qml side
    */
    cpp!(unsafe [] -> bool as "bool"{
        gst_init(nullptr,nullptr);
        // GstElement *pipeline = gst_pipeline_new (NULL);
        // GstElement *src = gst_element_factory_make ("videotestsrc", NULL);
        // GstElement *glupload = gst_element_factory_make ("glupload", NULL);
        GstElement *sink = gst_element_factory_make ("qml6glsink", NULL);
        if (!sink) {
            return false;
        }

        gst_object_unref(sink);

        return true;
    })
}


pub fn qvariant_to_ptr(item : QVariant) -> usize {
    cpp::cpp!(unsafe [item as "QVariant"] -> usize as "uintptr_t" {
        QObject* o = item.value<QObject *>();
        if (!o) return 0;

        // better do this
        QQuickItem* q = qobject_cast<QQuickItem*>(o);
        if (!q) return 0;

        return reinterpret_cast<uintptr_t>(q);
    })
}