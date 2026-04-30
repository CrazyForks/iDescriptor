#pragma once
#include "rust/cxx.h"
#include <QImage>

QImage load_heic(rust::Vec<uint8_t> data);