use ::log::debug;
use lru::LruCache;
use once_cell::sync::Lazy;
use qttypes::QImage;
use std::num::NonZeroUsize;
use std::sync::Mutex;

const IMAGE_CACHE_CAPACITY: usize = 512;

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct CacheKey {
    udid: String,
    path: String,
    afc2: bool,
    width: u32,
    height: u32,
}

impl CacheKey {
    fn new(udid: &str, path: &str, afc2: bool, width: u32, height: u32) -> Self {
        Self {
            udid: udid.to_string(),
            path: path.to_string(),
            afc2,
            width,
            height,
        }
    }
}

static CACHE: Lazy<Mutex<LruCache<CacheKey, QImage>>> = Lazy::new(|| {
    let capacity =
        NonZeroUsize::new(IMAGE_CACHE_CAPACITY).expect("image cache capacity is non-zero");
    Mutex::new(LruCache::new(capacity))
});

pub fn get(udid: &str, path: &str, afc2: bool, width: u32, height: u32) -> Option<QImage> {
    CACHE
        .lock()
        .ok()?
        .get(&CacheKey::new(udid, path, afc2, width, height))
        .cloned()
}

pub fn insert(udid: &str, path: &str, afc2: bool, width: u32, height: u32, img: QImage) {
    if let Ok(mut guard) = CACHE.lock() {
        guard.put(CacheKey::new(udid, path, afc2, width, height), img);
    }
}

pub fn clear() {
    if let Ok(mut guard) = CACHE.lock() {
        guard.clear();
    }
}

pub fn clear_for_udid(udid: &str) {
    if let Ok(mut guard) = CACHE.lock() {
        // lru doesn't have retain
        let keys: Vec<_> = guard
            .iter()
            .filter_map(|(key, _)| (key.udid == udid).then(|| key.clone()))
            .collect();

        debug!(
            "Clearing {} images from cache for UDID {}",
            keys.len(),
            udid
        );

        for key in keys {
            guard.pop(&key);
        }
    }
}
