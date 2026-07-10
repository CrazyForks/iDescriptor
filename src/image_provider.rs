use qmetaobject::*;
use qttypes::{QImage, QSize, QString};
use url::form_urlencoded;

use crate::qquickimageprovider_imp::*;

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

fn parse_image_id(id: &str) -> Option<(String, u32, String)> {
    let (path, query) = id.split_once('?').unwrap_or((id, ""));
    let mut udid = String::new();
    let mut index: u32 = 0;

    for (k, v) in form_urlencoded::parse(query.as_bytes()) {
        match k.as_ref() {
            "udid" => udid = v.into_owned(),
            "index" => index = v.parse().unwrap_or(0),
            _ => {}
        }
    }

    Some((udid, index, path.to_string()))
}

fn requested_cache_size(requested_size: &QSize) -> (u32, u32) {
    (requested_size.width, requested_size.height)
}

impl QQuickImageProvider for ImageProvider {
    fn request_image(&self, id: &str, requested_size: &QSize) -> (QSize, QImage) {
        let placeholder = (
            QSize {
                width: 500,
                height: 500,
            },
            QImage::load_from_file(QString::from(
                ":/resources/icons/material-symbols_image-outline-sharp.svg",
            )),
        );

        let (udid, index, path) = match parse_image_id(id) {
            Some(v) => v,
            None => {
                println!("Failed to parse image id: {}", id);
                return placeholder;
            }
        };

        let (width, height) = requested_cache_size(requested_size);

        if let Some(img) = crate::image_cache::get(&udid, &path, width, height) {
            return (
                QSize {
                    width: 500,
                    height: 500,
                },
                img,
            );
        }

        self.loader.pinned().clone().borrow_mut().request_thumbnail(
            QString::from(udid),
            QString::from(path),
            index,
            width,
            height,
        );

        placeholder
    }
}
