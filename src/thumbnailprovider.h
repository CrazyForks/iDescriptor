#include "idescriptor_rust_codebase/src/image_loader.cxxqt.h"
#include <QCache>
#include <QQuickImageProvider>
#include <QUrlQuery>

class ThumbnailProvider : public QQuickImageProvider
{
    Q_OBJECT
public:
    ThumbnailProvider() : QQuickImageProvider(Image)
    {
        // 350 MB
        m_cache.setMaxCost(350 * 1024 * 1024);
        connect(&m_imageLoader, &ImageBackend::thumbnail_ready, this,
                [this](const QString &path, const QImage &img,
                       unsigned int rowHint) {
                    insert(path, img);
                    qDebug() << "thumb ready in provider" << path << "Row"
                             << rowHint;
                    emit thumbnailReady(path, img, rowHint);
                });
    }

    static ThumbnailProvider *sharedInstance()
    {
        static auto *instance = new ThumbnailProvider();
        return instance;
    }

    QImage requestImage(const QString &id, QSize *size,
                        const QSize &requestedSize) override
    {
        const QUrl url(QStringLiteral("image://thumb/") + id);
        const QString path = url.path().mid(1); // strip leading '/'
        const QUrlQuery query(url);
        const QString udid = query.queryItemValue("udid");
        const qint32 index = query.queryItemValue("index").toInt();

        // FIXME: dont use path for key
        if (m_cache.contains(path)) {
            qDebug() << "Serving from provider cache";
            const QImage img = *m_cache.object(path);
            if (size)
                *size = img.size();
            return img;
        }

        qDebug() << "path" << path << "udid" << udid;

        m_imageLoader.request_thumbnail(udid, path, index);

        const QString resPath = QStringLiteral(
            ":/resources/icons/MaterialSymbolsLightImageOutlineSharp.png");
        qDebug() << "ThumbnailProvider: requestImage id=" << id
                 << " requestedSize=" << requestedSize;

        QImage placeholder(resPath);

        if (size)
            *size = placeholder.size();
        return placeholder;
    }

    void insert(const QString &id, const QImage &img)
    {
        QImage *heapImg = new QImage(img);

        int cacheCost =
            heapImg->width() * heapImg->height() * heapImg->depth() / 8;
        m_cache.insert(id, heapImg, cacheCost);
    }
signals:
    void thumbnailReady(const QString &path, const QImage &data,
                        unsigned int rowHint);

private:
    QCache<QString, QImage> m_cache;
    ImageBackend m_imageLoader;
};