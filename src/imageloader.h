#ifndef IMAGELOADER_H
#define IMAGELOADER_H

#include "iDescriptor.h"
#include <QCache>
#include <QHash>
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QSet>
#include <QString>
#include <QThreadPool>

class ImageTask;

class ImageLoader : public QObject
{
    Q_OBJECT
public:
    explicit ImageLoader(QObject *parent = nullptr);
    static ImageLoader &sharedInstance()
    {
        static ImageLoader instance;
        return instance;
    }
    void requestThumbnail(const iDescriptorDevice *device, const QString &path,
                          unsigned int row = 0);
    void
    requestImageWithCallback(const iDescriptorDevice *device,
                             const QString &path, int priority,
                             std::function<void(const QPixmap &)> callback);
    void cancelThumbnail(const QString &path);
    bool isLoading(const QString &path);
    void clear();
    QCache<QString, QPixmap> m_cache;
    static QPixmap loadThumbnailFromDevice(const iDescriptorDevice *device,
                                           const QString &filePath,
                                           const QSize &size);
    static QPixmap generateVideoThumbnailFFmpeg(const iDescriptorDevice *device,
                                                const QString &filePath,
                                                const QSize &size);
    static QPixmap loadImage(const iDescriptorDevice *device,
                             const QString &filePath);
signals:
    void thumbnailReady(const QString &path, const QPixmap &image,
                        unsigned int row);

private slots:
    void onTaskFinished(const QString &path, const QPixmap &image,
                        unsigned int row);

private:
    QThreadPool m_pool;
    QHash<QString, ImageTask *> m_pendingTasks;
    QMutex m_mutex;
};

#endif // IMAGELOADER_H