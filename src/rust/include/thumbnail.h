#pragma once
#include "rust/cxx.h"
#include <QImage>

class AfcReader;

QImage generate_thumbnail_with_reader(const AfcReader &reader,
                                      int32_t file_size, int32_t requested_w,
                                      int32_t requested_h);