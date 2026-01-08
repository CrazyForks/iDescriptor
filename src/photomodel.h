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

#ifndef PHOTOMODEL_H
#define PHOTOMODEL_H

#include "iDescriptor.h"
#include <QAbstractListModel>
#include <QCache>
#include <QCryptographicHash>
#include <QDateTime>
#include <QFutureWatcher>
#include <QPixmap>
#include <QSemaphore>
#include <QSize>
#include <QStandardPaths>

struct PhotoInfo {
    QString filePath;
    QString fileName;
    QDateTime dateTime;
    bool thumbnailRequested = false;

    enum FileType { Image, Video };
    FileType fileType;
};

class PhotoModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum SortOrder { NewestFirst, OldestFirst };

    enum FilterType { All, ImagesOnly, VideosOnly };

    explicit PhotoModel(iDescriptorDevice *device, FilterType filterType,
                        QObject *parent = nullptr);
    ~PhotoModel();

    // QAbstractItemModel interface
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index,
                  int role = Qt::DisplayRole) const override;

    // Album management
    void setAlbumPath(const QString &albumPath);
    void refreshPhotos();

    // Sorting and filtering
    void setSortOrder(SortOrder order);
    SortOrder sortOrder() const { return m_sortOrder; }

    void setFilterType(FilterType filter);
    FilterType filterType() const { return m_filterType; }

    // Export functionality
    QStringList getSelectedFilePaths(const QModelIndexList &indexes) const;
    QString getFilePath(const QModelIndex &index) const;
    PhotoInfo::FileType getFileType(const QModelIndex &index) const;

    // Get all items for export
    QStringList getAllFilePaths() const;
    QStringList getFilteredFilePaths() const;

    static QPixmap loadImage(iDescriptorDevice *device,
                             const QString &filePath);
    // Static helper methods
    static QPixmap loadThumbnailFromDevice(iDescriptorDevice *device,
                                           const QString &filePath,
                                           const QSize &size);
    void clear();
signals:
    void thumbnailNeedsToBeLoaded(int index);
    void exportRequested(const QStringList &filePaths);

public slots:
    void requestThumbnail(int index);

private:
    // Data members
    iDescriptorDevice *m_device;
    QString m_albumPath;
    QList<PhotoInfo> m_allPhotos; // All photos from device
    QList<PhotoInfo> m_photos;    // Currently filtered/sorted photos

    // Thumbnail management
    QSize m_thumbnailSize;
    mutable QCache<QString, QPixmap> m_thumbnailCache;
    mutable QHash<QString, QFutureWatcher<QPixmap> *> m_activeLoaders;
    mutable QSet<QString> m_loadingPaths;

    // Sorting and filtering
    SortOrder m_sortOrder;
    FilterType m_filterType;

    // Helper methods
    void populatePhotoPaths();
    void applyFilterAndSort();
    void sortPhotos(QList<PhotoInfo> &photos) const;
    bool matchesFilter(const PhotoInfo &info) const;

    QDateTime extractDateTimeFromFile(const QString &filePath) const;
    PhotoInfo::FileType determineFileType(const QString &fileName) const;

    static QPixmap generateVideoThumbnailFFmpeg(iDescriptorDevice *device,
                                                const QString &filePath,
                                                const QSize &requestedSize);
    static QSemaphore m_videoThumbnailSemaphore;
};

#endif // PHOTOMODEL_H