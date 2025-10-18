#ifndef PHOTOIMPORTDIALOG_H
#define PHOTOIMPORTDIALOG_H

#include <QDialog>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QProgressBar>
#include <QPushButton>
#include <QStringList>
#include <QVBoxLayout>

class SimpleHttpServer;

class PhotoImportDialog : public QDialog
{
    Q_OBJECT

public:
    explicit PhotoImportDialog(const QStringList &files, bool hasDirectories,
                               QWidget *parent = nullptr);
    ~PhotoImportDialog();

private slots:
    void init();
    void onServerStarted();
    void onServerError(const QString &error);
    void onDownloadProgress(const QString &fileName, int bytesDownloaded,
                            int totalBytes);

private:
    QStringList selectedFiles;
    bool containsDirectories;

    QListWidget *fileList;
    QLabel *warningLabel;
    QLabel *qrCodeLabel;
    QLabel *instructionLabel;
    QPushButton *m_cancelButton;
    QProgressBar *progressBar;
    QLabel *progressLabel;

    SimpleHttpServer *m_httpServer;

    void setupUI();
    void generateQRCode(const QString &url);
    QString getLocalIP() const;
};

#endif // PHOTOIMPORTDIALOG_H
