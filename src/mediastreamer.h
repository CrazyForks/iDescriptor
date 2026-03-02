/*
 * iDescriptor: A free and open-source idevice management tool.
 *
 * Copyright (C) 2025 Uncore <https://github.com/uncor3>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef MEDIASTREAMER_H
#define MEDIASTREAMER_H

#include "iDescriptor.h"
#include <QMap>
#include <QMutex>
#include <QTcpServer>
#include <QUrl>

QT_BEGIN_NAMESPACE
class QTcpSocket;
QT_END_NAMESPACE

class MediaStreamer : public QTcpServer
{
    Q_OBJECT

public:
    explicit MediaStreamer(const iDescriptorDevice *device,
                           AfcClientHandle *afcClient, const QString &filePath,
                           QObject *parent = nullptr);
    ~MediaStreamer();

    QUrl getUrl() const;
    bool isListening() const;

protected:
    void incomingConnection(qintptr socketDescriptor) override;

private slots:
    void handleClientDisconnected();

private:
    struct HttpRequest {
        QString method;
        QString path;
        QString httpVersion;
        QMap<QString, QString> headers;
        bool hasRange = false;
        qint64 rangeStart = 0;
        qint64 rangeEnd = -1;
    };

    struct StreamingContext {
        QTcpSocket *socket;
        const iDescriptorDevice *device;
        QString filePath;
        qint64 startByte;
        qint64 endByte;
        qint64 bytesRemaining;
        AfcFileHandle *afcHandle;
    };

    HttpRequest parseHttpRequest(const QByteArray &requestData);
    void handleRequest(QTcpSocket *socket, const HttpRequest &request);
    void sendErrorResponse(QTcpSocket *socket, int statusCode,
                           const QString &statusText);
    void streamFileRange(QTcpSocket *socket, qint64 startByte, qint64 endByte);
    void streamNextChunk(StreamingContext *context);
    void cleanupStreamingContext(StreamingContext *context);
    qint64 getFileSize();
    QString getMimeType() const;

    // Core data
    const iDescriptorDevice *m_device;
    QString m_filePath;

    // File info cache
    mutable QMutex m_fileSizeMutex;
    mutable qint64 m_cachedFileSize;
    mutable bool m_fileSizeCached;

    // Connection management
    QList<QTcpSocket *> m_activeConnections;
    QMutex m_connectionsMutex;

    AfcClientHandle *m_afcClient;
};

#endif // MEDIASTREAMER_H
