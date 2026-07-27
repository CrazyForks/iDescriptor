use cpp::cpp;
use log::warn;
use qmetaobject::prelude::*;
use qmetaobject::qtdeclarative::{QQuickItem, QQuickPaintedItem};
use qttypes::{QByteArray, QImage, QPainter, QPointF, QRectF};

cpp! {{
    #include <QtQuick/QQuickPaintedItem>
}}

#[derive(QObject, Default)]
pub struct QmlImage {
    base: qt_base_class!(trait QQuickPaintedItem),

    image: QImage,
    rotation_degrees: qt_property!(i32; NOTIFY rotation_degrees_changed),
    rotation_degrees_changed: qt_signal!(),
    mirror_horizontal: qt_property!(bool; NOTIFY mirror_horizontal_changed),
    mirror_horizontal_changed: qt_signal!(),

    set_frame: qt_method!(fn(&mut self, data: QByteArray)),
    update_paint: qt_method!(fn(&mut self)),
}

impl QQuickItem for QmlImage {}

impl QQuickPaintedItem for QmlImage {
    fn paint(&mut self, p: &mut QPainter) {
        let image_size = self.image.size();
        if image_size.width == 0 || image_size.height == 0 {
            return;
        }

        let bounds = self.item_bounds();
        let width = bounds.width;
        let height = bounds.height;
        if width <= 0.0 || height <= 0.0 {
            return;
        }

        let normalized_rotation = self.rotation_degrees.rem_euclid(360);
        let rotated_sideways = normalized_rotation == 90 || normalized_rotation == 270;
        let target_width = if rotated_sideways { height } else { width };
        let target_height = if rotated_sideways { width } else { height };

        let image_width = image_size.width as f64;
        let image_height = image_size.height as f64;
        let scale = (target_width / image_width).min(target_height / image_height);
        let draw_width = image_width * scale;
        let draw_height = image_height * scale;

        p.save();
        p.translate(QPointF {
            x: width / 2.0,
            y: height / 2.0,
        });
        if self.mirror_horizontal {
            p.scale(-1.0, 1.0);
        }
        p.rotate(normalized_rotation as f64);
        p.draw_image_fit_rect(
            QRectF {
                x: -draw_width / 2.0,
                y: -draw_height / 2.0,
                width: draw_width,
                height: draw_height,
            },
            self.image.clone(),
        );
        p.restore();
    }
}

impl QmlImage {
    fn set_frame(&mut self, data: QByteArray) {
        let image = crate::utils::create_image_from_buffer(data.to_slice(), 0, 0);
        if image.size().width == 0 || image.size().height == 0 {
            warn!("live screen received an invalid screenshot frame");
            return;
        }

        self.image = image;
        self.request_update();
    }

    fn update_paint(&mut self) {
        self.request_update();
    }

    fn item_bounds(&self) -> QRectF {
        let obj = self.get_cpp_object();
        cpp!(unsafe [obj as "void*"] -> QRectF as "QRectF" {
            auto item = reinterpret_cast<QQuickPaintedItem *>(obj);
            return item ? item->boundingRect() : QRectF();
        })
    }

    fn request_update(&self) {
        let obj = self.get_cpp_object();
        cpp!(unsafe [obj as "void*"] {
            auto item = reinterpret_cast<QQuickPaintedItem *>(obj);
            if (item) item->update();
        });
    }
}
