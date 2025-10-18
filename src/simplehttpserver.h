#ifndef SIMPLEHTTPSERVER_H
#define SIMPLEHTTPSERVER_H

#include <QMap>
#include <QObject>
#include <QStringList>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>

class SimpleHttpServer : public QObject
{
    Q_OBJECT

public:
    explicit SimpleHttpServer(QObject *parent = nullptr);
    ~SimpleHttpServer();

    void start(const QStringList &files);
    void stop();
    int getPort() const;
    QString getJsonFileName() const { return jsonFileName; }
signals:
    void serverStarted();
    void serverError(const QString &error);
    void downloadProgress(const QString &fileName, int bytesDownloaded,
                          int totalBytes);

private slots:
    void onNewConnection();
    void onReadyRead();
    void onDisconnected();

private:
    QTcpServer *server;
    QStringList fileList;
    int port;
    QString jsonFileName;
    QMap<QString, int> downloadTracker;

    void handleRequest(QTcpSocket *socket, const QString &path);
    void sendResponse(QTcpSocket *socket, int statusCode,
                      const QString &contentType, const QByteArray &data);
    void sendFile(QTcpSocket *socket, const QString &filePath);
    void sendJsonManifest(QTcpSocket *socket);
    void sendHtmlPage(QTcpSocket *socket);
    QString generateJsonManifest() const;
    QString generateHtmlPage() const;
    QString getMimeType(const QString &filePath) const;
    QString getLocalIP() const;
};

#endif // SIMPLEHTTPSERVER_H
