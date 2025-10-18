#include "photoimportdialog.h"
#include "simplehttpserver.h"
#include <QApplication>
#include <QDateTime>
#include <QFileInfo>
#include <QMessageBox>
#include <QNetworkInterface>
#include <QPainter>
#include <QPixmap>
#include <QRandomGenerator>
#include <qrencode.h>

PhotoImportDialog::PhotoImportDialog(const QStringList &files,
                                     bool hasDirectories, QWidget *parent)
    : QDialog(parent), selectedFiles(files),
      containsDirectories(hasDirectories), m_httpServer(nullptr)
{
    setupUI();
    setModal(true);
    resize(600, 500);
    setWindowTitle("Import Photos to iDevice - iDescriptor");
}

PhotoImportDialog::~PhotoImportDialog()
{
    if (m_httpServer) {
        m_httpServer->stop();
        delete m_httpServer;
    }
}

void PhotoImportDialog::setupUI()
{
    QVBoxLayout *mainLayout = new QVBoxLayout(this);

    // Warning label for directories
    if (containsDirectories) {
        warningLabel =
            new QLabel("⚠️ Warning: Selected items contain directories. All "
                       "gallery-compatible files will be included.",
                       this);
        warningLabel->setWordWrap(true);
        mainLayout->addWidget(warningLabel);
    }

    // File list
    QLabel *listLabel = new QLabel(
        QString("Files to be served (%1 items):").arg(selectedFiles.size()),
        this);
    mainLayout->addWidget(listLabel);

    fileList = new QListWidget(this);
    fileList->setMaximumHeight(150);
    for (const QString &file : selectedFiles) {
        QFileInfo info(file);
        fileList->addItem(info.fileName());
    }
    mainLayout->addWidget(fileList);

    // QR Code area
    qrCodeLabel = new QLabel(this);
    qrCodeLabel->setAlignment(Qt::AlignCenter);
    qrCodeLabel->setMinimumSize(200, 200);
    qrCodeLabel->setText("QR Code will appear here after starting server");
    mainLayout->addWidget(qrCodeLabel);

    // Instructions
    instructionLabel = new QLabel("Loading", this);
    mainLayout->addWidget(instructionLabel);

    // Progress tracking
    progressLabel = new QLabel("Download progress will appear here", this);
    progressLabel->setVisible(false);
    mainLayout->addWidget(progressLabel);

    // Progress bar
    progressBar = new QProgressBar(this);
    progressBar->setVisible(false);
    mainLayout->addWidget(progressBar);

    // Buttons
    QHBoxLayout *buttonLayout = new QHBoxLayout();
    m_cancelButton = new QPushButton("Cancel", this);

    buttonLayout->addStretch();
    buttonLayout->addWidget(m_cancelButton);

    mainLayout->addLayout(buttonLayout);

    connect(m_cancelButton, &QPushButton::clicked, this, &QDialog::reject);

    QTimer::singleShot(0, this, &PhotoImportDialog::init);
}

void PhotoImportDialog::init()
{
    progressBar->setVisible(true);
    progressBar->setRange(0, 0); // Indeterminate progress

    // Create and start HTTP server
    m_httpServer = new SimpleHttpServer(this);
    connect(m_httpServer, &SimpleHttpServer::serverStarted, this,
            &PhotoImportDialog::onServerStarted);
    connect(m_httpServer, &SimpleHttpServer::serverError, this,
            &PhotoImportDialog::onServerError);
    connect(m_httpServer, &SimpleHttpServer::downloadProgress, this,
            &PhotoImportDialog::onDownloadProgress);

    m_httpServer->start(selectedFiles);
}

void PhotoImportDialog::onServerStarted()
{
    progressBar->setVisible(false);

    QString localIP = getLocalIP();
    int port = m_httpServer->getPort();
    QString jsonFileName = m_httpServer->getJsonFileName();

    generateQRCode(
        QString("http://192.168.1.149:5173/?local=%1&port=%2&file=%3")
            // QString("https://uncor3.github.io/test-2?local=%1&port=%2&file=%3")
            .arg(localIP)
            .arg(port)
            .arg(jsonFileName));

    instructionLabel->setText(
        QString("Server started at %1:%2\n\n1. Scan the QR code to open the "
                "web interface\n2. Copy the server address and download the "
                "shortcut\n3. Run the shortcut on your iOS device")
            .arg(localIP)
            .arg(port));

    progressLabel->setVisible(true);
    progressLabel->setText("Waiting for downloads...");
}

void PhotoImportDialog::onDownloadProgress(const QString &fileName,
                                           int bytesDownloaded, int totalBytes)
{
    progressLabel->setText(QString("Downloaded: %1 (%2 KB)")
                               .arg(fileName)
                               .arg(bytesDownloaded / 1024));
}

void PhotoImportDialog::onServerError(const QString &error)
{
    progressBar->setVisible(false);
    m_cancelButton->setEnabled(true);

    QMessageBox::critical(this, "Server Error",
                          QString("Failed to start server: %1").arg(error));
    QDialog::reject();
}

void PhotoImportDialog::generateQRCode(const QString &url)
{
    QRcode *qrcode = QRcode_encodeString(url.toUtf8().constData(), 0,
                                         QR_ECLEVEL_M, QR_MODE_8, 1);
    if (!qrcode) {
        qrCodeLabel->setText("Failed to generate QR code");
        return;
    }

    int qrSize = 200;
    int qrWidth = qrcode->width;
    int scale = qrSize / qrWidth;
    if (scale < 1)
        scale = 1;

    QPixmap qrPixmap(qrWidth * scale, qrWidth * scale);
    qrPixmap.fill(Qt::white);

    QPainter painter(&qrPixmap);
    painter.setPen(Qt::NoPen);
    painter.setBrush(Qt::black);

    for (int y = 0; y < qrWidth; y++) {
        for (int x = 0; x < qrWidth; x++) {
            if (qrcode->data[y * qrWidth + x] & 1) {
                QRect rect(x * scale, y * scale, scale, scale);
                painter.drawRect(rect);
            }
        }
    }

    qrCodeLabel->setPixmap(qrPixmap);
    QRcode_free(qrcode);
}

QString PhotoImportDialog::getLocalIP() const
{
    foreach (const QNetworkInterface &interface,
             QNetworkInterface::allInterfaces()) {
        if (interface.flags().testFlag(QNetworkInterface::IsUp) &&
            !interface.flags().testFlag(QNetworkInterface::IsLoopBack)) {
            foreach (const QNetworkAddressEntry &entry,
                     interface.addressEntries()) {
                if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol) {
                    return entry.ip().toString();
                }
            }
        }
    }
    return "127.0.0.1";
}
