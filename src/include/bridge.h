#pragma once
#include <QtGui/QImage>
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*AfcReadCallback)(const void *reader_ptr, int64_t offset,
                                int32_t size, uint8_t *out_buf,
                                int32_t *out_len);

QImage generate_thumbnail_with_reader_ffi(const void *reader_ptr,
                                          int32_t file_size,
                                          int32_t requested_w,
                                          int32_t requested_h);

#ifdef __cplusplus
}
#endif