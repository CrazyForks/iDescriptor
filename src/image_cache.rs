use once_cell::sync::Lazy;
use qttypes::QImage;
use std::collections::HashMap;
use std::sync::Mutex;

static CACHE: Lazy<Mutex<HashMap<String, QImage>>> = Lazy::new(|| Mutex::new(HashMap::new()));

fn key(udid: &str, path: &str) -> String {
    // stable + avoids accidental collisions
    format!("{udid}\u{1f}{path}")
}

pub fn get(udid: &str, path: &str) -> Option<QImage> {
    CACHE.lock().ok()?.get(&key(udid, path)).cloned()
}

pub fn insert(udid: &str, path: &str, img: QImage) {
    if let Ok(mut guard) = CACHE.lock() {
        guard.insert(key(udid, path), img);
    }
}

pub fn clear() {
    if let Ok(mut guard) = CACHE.lock() {
        guard.clear();
    }
}
