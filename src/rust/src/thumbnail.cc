#include "bridge.h"
#include "rust/cxx.h"
#include <QImage>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/display.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

#include "idescriptor_rust_codebase/src/bridge.cxxqt.h"

QImage generate_thumbnail_with_reader(const AfcReader &reader,
                                      int32_t file_size, int32_t requested_w,
                                      int32_t requested_h)
{
    QImage result;

    AVFormatContext *formatCtx = avformat_alloc_context();
    if (!formatCtx) {
        // qWarning() << "Failed to allocate format context";
        return result;
    }

    struct StreamContext {
        const AfcReader *reader;
        int32_t fileSize;
        int currentPos;
    };

    auto *streamCtx = new StreamContext{&reader, file_size, 0};

    auto readPacket = [](void *opaque, uint8_t *buf, int bufSize) -> int {
        auto *ctx = static_cast<StreamContext *>(opaque);

        if (ctx->currentPos >= ctx->fileSize) {
            return AVERROR_EOF;
        }

        int toRead = std::min<int>(bufSize, ctx->fileSize - ctx->currentPos);
        auto data = ctx->reader->read_at(ctx->currentPos, toRead);

        if (data.empty()) {
            return (toRead == 0) ? AVERROR_EOF : AVERROR(EIO);
        }

        const int n = std::min<int>(data.size(), toRead);
        memcpy(buf, data.data(), n);
        ctx->currentPos += n;
        return n;
    };

    auto seekPacket = [](void *opaque, int64_t offset, int whence) -> int64_t {
        auto *ctx = static_cast<StreamContext *>(opaque);

        if (whence == AVSEEK_SIZE) {
            return ctx->fileSize;
        }

        int newPos = 0;
        switch (whence) {
        case SEEK_SET:
            newPos = offset;
            break;
        case SEEK_CUR:
            newPos = ctx->currentPos + offset;
            break;
        case SEEK_END:
            newPos = ctx->fileSize + offset;
            break;
        default:
            return -1;
        }

        if (newPos < 0 || newPos > ctx->fileSize) {
            return -1;
        }

        ctx->currentPos = newPos;
        return newPos;
    };

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

    // Open input
    if (avformat_open_input(&formatCtx, nullptr, nullptr, nullptr) < 0) {
        // qWarning() << "Failed to open video format";
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        avformat_free_context(formatCtx);
        return {};
    }

    // Find stream info
    if (avformat_find_stream_info(formatCtx, nullptr) < 0) {
        // qWarning() << "Failed to find stream info";
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        return {};
    }

    // Find video stream
    int videoStreamIndex = -1;
    const AVCodec *codec = nullptr;
    AVCodecParameters *codecParams = nullptr;

    for (unsigned int i = 0; i < formatCtx->nb_streams; i++) {
        if (formatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStreamIndex = i;
            codecParams = formatCtx->streams[i]->codecpar;
            codec = avcodec_find_decoder(codecParams->codec_id);
            break;
        }
    }

    if (videoStreamIndex == -1 || !codec) {
        // qWarning() << "No video stream found";
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        return {};
    }

    // Allocate codec context
    AVCodecContext *codecCtx = avcodec_alloc_context3(codec);
    if (!codecCtx) {
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        return {};
    }

    if (avcodec_parameters_to_context(codecCtx, codecParams) < 0) {
        avcodec_free_context(&codecCtx);
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        return {};
    }

    // Open codec
    if (avcodec_open2(codecCtx, codec, nullptr) < 0) {
        avcodec_free_context(&codecCtx);
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        return {};
    }

    // Allocate frame
    AVFrame *frame = av_frame_alloc();
    AVPacket *packet = av_packet_alloc();

    if (!frame || !packet) {
        if (frame)
            av_frame_free(&frame);
        if (packet)
            av_packet_free(&packet);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&formatCtx);
        av_free(avioCtx->buffer);
        avio_context_free(&avioCtx);
        return {};
    }

    // Read frames until we get a valid one
    bool frameDecoded = false;
    while (av_read_frame(formatCtx, packet) >= 0) {
        if (packet->stream_index == videoStreamIndex) {
            if (avcodec_send_packet(codecCtx, packet) >= 0) {
                if (avcodec_receive_frame(codecCtx, frame) >= 0) {
                    frameDecoded = true;
                    av_packet_unref(packet);
                    break;
                }
            }
        }
        av_packet_unref(packet);
    }

    if (frameDecoded) {
        // Get rotation from display matrix
        double rotation = 0.0;
        if (AVFrameSideData *sd =
                av_frame_get_side_data(frame, AV_FRAME_DATA_DISPLAYMATRIX)) {
            rotation =
                -av_display_rotation_get(reinterpret_cast<int32_t *>(sd->data));
        }

        // Convert frame to RGB24
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

                    // Convert to QImage
                    QImage img(rgbFrame->data[0], rgbFrame->width,
                               rgbFrame->height, rgbFrame->linesize[0],
                               QImage::Format_RGB888);

                    // Create a deep copy since AVFrame will be freed
                    QImage imgCopy = img.copy();

                    // Apply rotation
                    if (rotation != 0.0) {
                        QTransform transform;
                        transform.rotate(rotation);
                        imgCopy = imgCopy.transformed(transform);
                    }

                    result = imgCopy;
                    // FIXME: scale
                    // Scale to requested size
                    /*
                        TODO: scaling might become optional
                        if we ever needed the raw frame,
                        might need to abstract the main logic to get the
                        frame and handle scaling separately
                    */
                    // result =
                    //     imgCopy.scaled(requestedSize,
                    //     Qt::KeepAspectRatio,
                    //                    Qt::SmoothTransformation);
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

    return result;
}