use qmetaobject::*;
use qttypes::{QImage, QSize, QString};
use url::form_urlencoded;

use crate::qquickimageprovider_imp::*;

#[allow(dead_code)]
#[derive(Default, Clone)]
struct QSizeRef {
    inner: QSize,
}

impl QMetaType for QSizeRef {}

impl From<QSize> for QSizeRef {
    fn from(size: QSize) -> Self {
        Self { inner: size }
    }
}

#[derive(QObject)]
pub struct ImageProvider {
    base: qt_base_class!(trait QQuickImageProvider),
    loader: QObjectBox<crate::image_loader::ImageLoader>,
}

impl ImageProvider {
    pub fn default(loader: QObjectBox<crate::image_loader::ImageLoader>) -> Self {
        Self {
            loader: loader,
            base: Default::default(),
        }
    }
}

fn parse_image_id(id: &str) -> Option<(String, u32, String, bool)> {
    let (path, query) = id.split_once('?').unwrap_or((id, ""));
    let mut udid = String::new();
    let mut index: u32 = 0;
    let mut afc2 = false;

    for (k, v) in form_urlencoded::parse(query.as_bytes()) {
        match k.as_ref() {
            "udid" => udid = v.into_owned(),
            "index" => index = v.parse().unwrap_or(0),
            "afc2" => afc2 = v == "true" || v == "1",
            _ => {}
        }
    }

    let path = urlencoding::decode(path).ok()?.into_owned();
    Some((udid, index, path, afc2))
}

fn requested_cache_size(requested_size: &QSize) -> (u32, u32) {
    fn normalize_dimension(value: u32) -> u32 {
        // qttypes represents QSize dimensions as u32, so Qt's -1 sentinel for
        // an unspecified sourceSize crosses the FFI boundary as a large value.
        if value > i32::MAX as u32 { 0 } else { value }
    }

    (
        normalize_dimension(requested_size.width),
        normalize_dimension(requested_size.height),
    )
}

fn image_response(image: QImage) -> (QSize, QImage) {
    let size = image.size();
    (size, image)
}

impl QQuickImageProvider for ImageProvider {
    fn request_image(&self, id: &str, requested_size: &QSize) -> (QSize, QImage) {
        let placeholder = || {
            image_response(QImage::load_from_file(QString::from(
                ":/resources/icons/material-symbols_image-outline-sharp.svg",
            )))
        };

        let (udid, index, path, afc2) = match parse_image_id(id) {
            Some(v) => v,
            None => {
                println!("Failed to parse image id: {}", id);
                return placeholder();
            }
        };

        let (width, height) = requested_cache_size(requested_size);

        if let Some(img) = crate::image_cache::get(&udid, &path, afc2, width, height) {
            return image_response(img);
        }

        self.loader.pinned().borrow().request_thumbnail(
            QString::from(udid),
            QString::from(path),
            afc2,
            index,
            width,
            height,
        );

        placeholder()
    }
}
