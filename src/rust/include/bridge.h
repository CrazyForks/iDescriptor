#pragma once
#include "rust/cxx.h"
#include <QImage>

QImage heic_to_image(rust::Slice<const uint8_t> buf);

class AfcReader;

QImage generate_thumbnail_with_reader(const AfcReader &reader,
                                      int32_t file_size, int32_t requested_w,
                                      int32_t requested_h);

QString qinput_get_text(bool ok);