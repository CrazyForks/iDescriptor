use ::log::debug;
use lru::LruCache;
use once_cell::sync::Lazy;
use qttypes::QImage;
use std::num::NonZeroUsize;
use std::sync::Mutex;

const IMAGE_CACHE_CAPACITY: usize = 512;
const IMAGE_CACHE_MAX_BYTES: usize = 256 * 1024 * 1024;

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

struct CacheEntry {
    image: QImage,
    estimated_bytes: usize,
}

struct ImageCache {
    entries: LruCache<CacheKey, CacheEntry>,
    estimated_bytes: usize,
}

impl ImageCache {
    fn new() -> Self {
        let capacity =
            NonZeroUsize::new(IMAGE_CACHE_CAPACITY).expect("image cache capacity is non-zero");
        Self {
            entries: LruCache::new(capacity),
            estimated_bytes: 0,
        }
    }

    fn insert(&mut self, key: CacheKey, image: QImage) {
        let estimated_bytes = estimated_image_bytes(&image);
        let entry = CacheEntry {
            image,
            estimated_bytes,
        };

        if let Some((_, removed)) = self.entries.push(key, entry) {
            self.estimated_bytes = self.estimated_bytes.saturating_sub(removed.estimated_bytes);
        }
        self.estimated_bytes = self.estimated_bytes.saturating_add(estimated_bytes);

        // Keep a single oversized image so the provider's placeholder/reload
        // protocol can still complete instead of repeatedly missing the cache.
        while self.estimated_bytes > IMAGE_CACHE_MAX_BYTES && self.entries.len() > 1 {
            let Some((_, removed)) = self.entries.pop_lru() else {
                break;
            };
            self.estimated_bytes = self.estimated_bytes.saturating_sub(removed.estimated_bytes);
        }
    }

    fn clear(&mut self) {
        self.entries.clear();
        self.estimated_bytes = 0;
    }
}

fn estimated_image_bytes(image: &QImage) -> usize {
    let size = image.size();
    (size.width as usize)
        .saturating_mul(size.height as usize)
        .saturating_mul(4)
}

static CACHE: Lazy<Mutex<ImageCache>> = Lazy::new(|| Mutex::new(ImageCache::new()));

pub fn get(udid: &str, path: &str, afc2: bool, width: u32, height: u32) -> Option<QImage> {
    CACHE
        .lock()
        .ok()?
        .entries
        .get(&CacheKey::new(udid, path, afc2, width, height))
        .map(|entry| entry.image.clone())
}

pub fn insert(udid: &str, path: &str, afc2: bool, width: u32, height: u32, img: QImage) {
    if let Ok(mut guard) = CACHE.lock() {
        guard.insert(CacheKey::new(udid, path, afc2, width, height), img);
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
            .entries
            .iter()
            .filter_map(|(key, _)| (key.udid == udid).then(|| key.clone()))
            .collect();

        debug!(
            "Clearing {} images from cache for UDID {}",
            keys.len(),
            udid
        );

        for key in keys {
            if let Some(removed) = guard.entries.pop(&key) {
                guard.estimated_bytes = guard
                    .estimated_bytes
                    .saturating_sub(removed.estimated_bytes);
            }
        }
    }
}
