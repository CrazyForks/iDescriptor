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

#include "mediastreamermanager.h"
#include "mediastreamer.h"
#include <QDebug>
#include <QMutexLocker>

MediaStreamerManager::~MediaStreamerManager() { cleanup(); }

MediaStreamerManager *MediaStreamerManager::sharedInstance()
{
    static MediaStreamerManager instance;
    return &instance;
}

QUrl MediaStreamerManager::getStreamUrl(const iDescriptorDevice *device,
                                        AfcClientHandle *afcClient,
                                        const QString &filePath)
{
    QMutexLocker locker(&m_streamersMutex);

    // Check if we already have a streamer for this file
    auto it = m_streamers.find(filePath);
    if (it != m_streamers.end()) {
        // Verify the streamer is still valid and listening
        if (it->streamer && it->streamer->isListening()) {
            it->refCount++;
            qDebug() << "MediaStreamerManager: Reusing existing streamer for"
                     << filePath << "refCount:" << it->refCount;
            return it->streamer->getUrl();
        } else {
            // Clean up invalid streamer
            qDebug() << "MediaStreamerManager: Cleaning up invalid streamer for"
                     << filePath;
            if (it->streamer) {
                it->streamer->deleteLater();
            }
            m_streamers.erase(it);
        }
    }

    // Create new streamer without a QObject parent
    auto *streamer = new MediaStreamer(device, afcClient, filePath, nullptr);
    if (!streamer->isListening()) {
        qWarning() << "MediaStreamerManager: Failed to create streamer for"
                   << filePath;
        delete streamer;
        return QUrl();
    }

    // FIXME: device pointer can become dangling if device is disconnected
    StreamerInfo info;
    info.streamer = streamer;
    info.device = device;
    info.refCount = 1;
    m_streamers[filePath] = info;

    qDebug() << "MediaStreamerManager: Created new streamer for" << filePath
             << "at" << streamer->getUrl().toString();

    return streamer->getUrl();
}

void MediaStreamerManager::releaseStreamer(const QString &filePath)
{
    QMutexLocker locker(&m_streamersMutex);
    auto it = m_streamers.find(filePath);
    if (it != m_streamers.end()) {
        it->refCount--;
        qDebug() << "MediaStreamerManager: Released streamer for" << filePath
                 << "refCount:" << it->refCount;

        // If no more references, delete it immediately.
        // deleteLater() will not work in a thread without an event loop.
        if (it->refCount <= 0) {
            qDebug() << "MediaStreamerManager: Deleting streamer for"
                     << filePath;
            delete it->streamer;
            m_streamers.erase(it);
        }
    }
}

void MediaStreamerManager::cleanup()
{
    QMutexLocker locker(&m_streamersMutex);
    auto it = m_streamers.begin();
    while (it != m_streamers.end()) {
        qDebug() << "MediaStreamerManager: Cleaning up streamer for"
                 << it.key();
        if (it->streamer) {
            delete it->streamer;
        }
        it = m_streamers.erase(it);
    }
}