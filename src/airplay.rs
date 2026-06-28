use crate::qt_threading::{QtThread, QtThreading};
use log::debug;
use macros::QtThreading;
use qmetaobject::prelude::*;

use once_cell::sync::OnceCell;
use std::ffi::CString;
use std::os::raw::c_void;
use std::os::raw::{c_char, c_int};
use std::sync::atomic::AtomicUsize;
use std::sync::atomic::Ordering;

static VIDEO_ITEM_PTR: AtomicUsize = AtomicUsize::new(0);
static AIRPLAY_QT_THREAD: OnceCell<QtThread<Airplay>> = OnceCell::new();

unsafe extern "C" {
    fn init_uxplay(argc: c_int, argv: *mut *mut c_char) -> c_int;
    fn uxplay_cleanup();

    fn set_uxplay_gl_callbacks(
        connection_cb: extern "C" fn(bool),
        get_video_item_cb: extern "C" fn() -> *mut c_void,
    );
}

extern "C" fn rust_uxplay_get_video_item() -> *mut c_void {
    VIDEO_ITEM_PTR.load(Ordering::Acquire) as *mut c_void
}

extern "C" fn rust_uxplay_connection_cb(connected: bool) {
    debug!("AirPlay connection changed: {}", connected);
    if let Some(q_thread) = AIRPLAY_QT_THREAD.get() {
        q_thread.queue(move |t| {
            t.connection_change(connected);
        });
    }
}

#[derive(QObject, Default, QtThreading)]
pub struct Airplay {
    base: qt_base_class!(trait QObject),
    init: qt_method!(fn(&self, video_item: QVariant) -> bool),
    cleanup: qt_method!(fn(&self)),
    load_gst_gl: qt_method!(fn(&self) -> bool),
    connection_change: qt_signal!(connected: bool),
}

impl Airplay {
    fn load_gst_gl(&self) -> bool {
        crate::utils::force_load_gst_gl()
    }

    fn init(&self, video_item: QVariant) -> bool {
        AIRPLAY_QT_THREAD.get_or_init(|| self.qt_thread());

        let ptr = crate::utils::qvariant_to_ptr(video_item);

        VIDEO_ITEM_PTR.store(ptr as usize, Ordering::Release);
        unsafe {
            set_uxplay_gl_callbacks(rust_uxplay_connection_cb, rust_uxplay_get_video_item);
        }

        std::thread::spawn(|| {
            let args = crate::settings_manager::airplay_uxplay_args();
            debug!("Starting uxplay with args: {:?}", args);

            let c_strings: Vec<CString> = args
                .into_iter()
                .filter_map(|arg| CString::new(arg).ok())
                .collect();
            let mut c_args: Vec<*mut c_char> = c_strings
                .iter()
                .map(|arg| arg.as_ptr() as *mut c_char)
                .collect();
            c_args.push(std::ptr::null_mut());

            unsafe {
                init_uxplay((c_args.len() - 1) as i32, c_args.as_mut_ptr());
            }
        });
        true
    }

    fn cleanup(&self) {
        unsafe {
            uxplay_cleanup();
        }
    }
}
