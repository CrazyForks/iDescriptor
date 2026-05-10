#include "include/bridge.h"
#include <QImage>
#include <QTransform>
#include <algorithm>
#include <cstring>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/display.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

/* this is declared in Rust with #[no_mangle]*/
extern "C" void afc_reader_read_at(const void *reader_ptr, int64_t offset,
                                   int32_t size, uint8_t *out_buf,
                                   int32_t *out_len);

QImage generate_thumbnail_with_reader_ffi(const void *reader_ptr,
                                          int32_t file_size,
                                          int32_t requested_w,
                                          int32_t requested_h)
{
    struct StreamContext {
        const void *readerPtr;
        int32_t fileSize;
        int currentPos;
    };

    auto *streamCtx = new StreamContext{reader_ptr, file_size, 0};

    auto readPacket = [](void *opaque, uint8_t *buf, int bufSize) -> int {
        auto *ctx = static_cast<StreamContext *>(opaque);
        if (ctx->currentPos >= ctx->fileSize)
            return AVERROR_EOF;

        int toRead = std::min<int>(bufSize, ctx->fileSize - ctx->currentPos);
        int32_t got = 0;
        afc_reader_read_at(ctx->readerPtr, ctx->currentPos, toRead, buf, &got);

        if (got <= 0)
            return (toRead == 0) ? AVERROR_EOF : AVERROR(EIO);

        ctx->currentPos += got;
        return got;
    };

    auto seekPacket = [](void *opaque, int64_t offset, int whence) -> int64_t {
        auto *ctx = static_cast<StreamContext *>(opaque);
        if (whence == AVSEEK_SIZE)
            return ctx->fileSize;

        int newPos = 0;
        switch (whence) {
        case SEEK_SET:
            newPos = (int)offset;
            break;
        case SEEK_CUR:
            newPos = ctx->currentPos + (int)offset;
            break;
        case SEEK_END:
            newPos = ctx->fileSize + (int)offset;
            break;
        default:
            return -1;
        }
        if (newPos < 0 || newPos > ctx->fileSize)
            return -1;
        ctx->currentPos = newPos;
        return newPos;
    };

    AVFormatContext *formatCtx = avformat_alloc_context();
    if (!formatCtx) {
        delete streamCtx;
        return {};
    }

    const int avioBufferSize = 32768;
    unsigned char *avioBuffer =
        static_cast<unsigned char *>(av_malloc(avioBufferSize));
    if (!avioBuffer) {
        delete streamCtx;
        avformat_free_context(formatCtx);
        return {};
    }

    AVIOContext *avioCtx =
        avio_alloc_context(avioBuffer, avioBufferSize, 0, streamCtx, readPacket,
                           nullptr, seekPacket);
    if (!avioCtx) {
        av_free(avioBuffer);
        delete streamCtx;
        avformat_free_context(formatCtx);
        return {};
    }

    formatCtx->pb = avioCtx;
    formatCtx->flags |= AVFMT_FLAG_CUSTOM_IO;

    if (avformat_open_input(&formatCtx, nullptr, nullptr, nullptr) < 0) {
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        delete streamCtx;
        return {};
    }

    if (avformat_find_stream_info(formatCtx, nullptr) < 0) {
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        delete streamCtx;
        return {};
    }

    int videoStreamIndex = -1;
    const AVCodec *codec = nullptr;
    AVCodecParameters *codecParams = nullptr;

    for (unsigned i = 0; i < formatCtx->nb_streams; i++) {
        if (formatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStreamIndex = i;
            codecParams = formatCtx->streams[i]->codecpar;
            codec = avcodec_find_decoder(codecParams->codec_id);
            break;
        }
    }

    if (videoStreamIndex == -1 || !codec) {
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        delete streamCtx;
        return {};
    }

    AVCodecContext *codecCtx = avcodec_alloc_context3(codec);
    if (!codecCtx || avcodec_parameters_to_context(codecCtx, codecParams) < 0 ||
        avcodec_open2(codecCtx, codec, nullptr) < 0) {
        if (codecCtx)
            avcodec_free_context(&codecCtx);
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        delete streamCtx;
        return {};
    }

    AVFrame *frame = av_frame_alloc();
    AVPacket *packet = av_packet_alloc();

    // first video frame ─────────────────────────────────────────────
    if (!frame || !packet) {
        if (frame)
            av_frame_free(&frame);
        if (packet)
            av_packet_free(&packet);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        delete streamCtx;
        return {};
    }

    bool frameDecoded = false;
    while (av_read_frame(formatCtx, packet) >= 0) {
        if (packet->stream_index == videoStreamIndex) {
            if (avcodec_send_packet(codecCtx, packet) >= 0 &&
                avcodec_receive_frame(codecCtx, frame) >= 0) {
                frameDecoded = true;
                av_packet_unref(packet);
                break;
            }
        }
        av_packet_unref(packet);
    }

    QImage result;

    if (frameDecoded) {
        double rotation = 0.0;
        if (AVFrameSideData *sd =
                av_frame_get_side_data(frame, AV_FRAME_DATA_DISPLAYMATRIX)) {
            rotation =
                -av_display_rotation_get(reinterpret_cast<int32_t *>(sd->data));
        }

        SwsContext *swsCtx =
            sws_getContext(frame->width, frame->height,
                           static_cast<AVPixelFormat>(frame->format),
                           frame->width, frame->height, AV_PIX_FMT_RGB24,
                           SWS_BILINEAR, nullptr, nullptr, nullptr);

        if (swsCtx) {
            AVFrame *rgbFrame = av_frame_alloc();
            if (rgbFrame) {
                rgbFrame->format = AV_PIX_FMT_RGB24;
                rgbFrame->width = frame->width;
                rgbFrame->height = frame->height;

                if (av_frame_get_buffer(rgbFrame, 0) >= 0) {
                    sws_scale(swsCtx, frame->data, frame->linesize, 0,
                              frame->height, rgbFrame->data,
                              rgbFrame->linesize);

                    QImage img(rgbFrame->data[0], rgbFrame->width,
                               rgbFrame->height, rgbFrame->linesize[0],
                               QImage::Format_RGB888);

                    // deep copy since rgbFrame will be freed
                    result = img.copy();

                    if (rotation != 0.0) {
                        QTransform t;
                        t.rotate(rotation);
                        result = result.transformed(t);
                    }

                    // scale
                    if (requested_w > 0 && requested_h > 0) {
                        result = result.scaled(requested_w, requested_h,
                                               Qt::KeepAspectRatio,
                                               Qt::SmoothTransformation);
                    }
                }
                av_frame_free(&rgbFrame);
            }
            sws_freeContext(swsCtx);
        }
    }

    // Cleanup
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&codecCtx);
    avformat_close_input(&formatCtx);
    delete streamCtx;

    return result;
}