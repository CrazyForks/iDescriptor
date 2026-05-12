use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use idevice::utils;
use ipatool::Account;
use ipatool::IpaTool;
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantMap};


use std::ffi::CString;
use std::os::raw::c_void;
use std::os::raw::{c_char, c_int};
use std::sync::atomic::AtomicUsize;
use std::sync::atomic::Ordering;
use cpp::*;

static VIDEO_ITEM_PTR : AtomicUsize = AtomicUsize::new(0); 

unsafe extern "C" {
    fn init_uxplay(argc: c_int, argv: *mut *mut c_char) -> c_int;

    fn set_uxplay_gl_callbacks(
        connection_cb: extern "C" fn(bool),
        get_video_item_cb: extern "C" fn() -> *mut c_void,
    );
}

extern "C" fn rust_uxplay_get_video_item() -> *mut c_void {
    VIDEO_ITEM_PTR.load(Ordering::Acquire) as *mut c_void
}


extern "C" fn rust_uxplay_connection_cb(connected : bool) {

}


#[derive(QObject, Default, QtThreading)]
pub struct Airplay {
    base: qt_base_class!(trait QObject),
    init : qt_method!(fn(&self, video_item : QVariant) -> bool),
    load_gst_gl : qt_method!(fn(&self) -> bool),
    connection_change : qt_signal!(connected: bool)
}

impl Airplay {

    fn load_gst_gl(&self) -> bool {
        crate::utils::force_load_gst_gl()        
    }

    fn init(&self, video_item: QVariant ) -> bool {

        let ptr = crate::utils::qvariant_to_ptr(video_item);

        VIDEO_ITEM_PTR.store(ptr as usize, Ordering::Release);
        unsafe  {
            set_uxplay_gl_callbacks(
                rust_uxplay_connection_cb,
                rust_uxplay_get_video_item
            );
        }

        std::thread::spawn(||{
            let arg0 = CString::new("uxplay").unwrap();
            let arg1 = CString::new("-p").unwrap();
            let arg2 =CString::new("-fps").unwrap();
            let arg3 =CString::new("60").unwrap();

            let mut c_args = vec![arg0.as_ptr() as *mut c_char, arg1.as_ptr() as *mut c_char, arg2.as_ptr() as *mut c_char,arg3.as_ptr() as *mut c_char, std::ptr::null_mut()];

            unsafe  {
                init_uxplay((c_args.len() - 1) as i32, c_args.as_mut_ptr());
            }
        });
        true
    }
}