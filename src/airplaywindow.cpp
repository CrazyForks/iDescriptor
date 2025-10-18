#include "airplaywindow.h"
#include <QApplication>
#include <QCheckBox>
#include <QCloseEvent>
#include <QDebug>
#include <QFileInfo>
#include <QFont>
#include <QHBoxLayout>
#include <QLabel>
#include <QMediaPlayer>
#include <QMessageBox>
#include <QPalette>
#include <QPixmap>
#include <QProcess>
#include <QStackedWidget>
#include <QVBoxLayout>
#include <QVideoWidget>

#ifdef Q_OS_LINUX
// V4L2 includes
#include <cstring>
#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <unistd.h>
#endif

// Include the rpiplay server functions
#include "../lib/airplay/renderers/video_renderer.h"
extern "C" {
int start_server_qt(const char *name, void *callbacks);
int stop_server_qt();
}

AirPlayWindow::AirPlayWindow(QWidget *parent)
    : QMainWindow(parent), m_stackedWidget(nullptr), m_tutorialWidget(nullptr),
      m_streamingWidget(nullptr), m_loadingIndicator(nullptr),
      m_loadingLabel(nullptr), m_tutorialPlayer(nullptr),
      m_tutorialVideoWidget(nullptr), m_videoLabel(nullptr),
      m_tutorialLayout(nullptr), m_v4l2Checkbox(nullptr),
      m_serverThread(nullptr), m_serverRunning(false)
#ifdef Q_OS_LINUX
      ,
      m_v4l2_fd(-1), m_v4l2_width(0), m_v4l2_height(0), m_v4l2_enabled(false)
#endif
{
    setupUI();

    // Auto-start server after UI setup
    QTimer::singleShot(500, this, &AirPlayWindow::startAirPlayServer);
}

AirPlayWindow::~AirPlayWindow()
{
    stopAirPlayServer();
#ifdef Q_OS_LINUX
    closeV4L2();
#endif
}

void AirPlayWindow::setupUI()
{
    setWindowTitle("AirPlay Receiver - iDescriptor");
    setMinimumSize(800, 600);
    resize(1000, 700);

    // Create stacked widget
    m_stackedWidget = new QStackedWidget(this);
    setCentralWidget(m_stackedWidget);

    m_tutorialWidget = new QWidget();
    m_tutorialLayout = new QVBoxLayout(m_tutorialWidget);
    m_tutorialLayout->setContentsMargins(40, 40, 40, 40);
    m_tutorialLayout->setSpacing(20);

    m_loadingIndicator = new QProcessIndicator();
    m_loadingIndicator->setType(QProcessIndicator::line_rotate);
    m_loadingIndicator->setFixedSize(64, 32);
    m_loadingIndicator->start();

    QHBoxLayout *loadingLayout = new QHBoxLayout();
    loadingLayout->setSpacing(1);
    m_loadingLabel = new QLabel("Starting AirPlay Server...");
    m_loadingLabel->setAlignment(Qt::AlignCenter);

    loadingLayout->addWidget(m_loadingLabel);
    loadingLayout->addWidget(m_loadingIndicator);

    m_tutorialLayout->addLayout(loadingLayout);
    m_tutorialLayout->addSpacing(1);

    QTimer::singleShot(100, this, &AirPlayWindow::setupTutorialVideo);

    m_streamingWidget = new QWidget();
    QVBoxLayout *streamingLayout = new QVBoxLayout(m_streamingWidget);
    streamingLayout->setContentsMargins(10, 10, 10, 10);
    streamingLayout->setSpacing(10);

#ifdef Q_OS_LINUX
    // Add V4L2 checkbox at the top of streaming view
    setupV4L2Checkbox();
    if (m_v4l2Checkbox) {
        streamingLayout->addWidget(m_v4l2Checkbox);
    }
#endif

    // Video display
    m_videoLabel = new QLabel();
    m_videoLabel->setMinimumSize(640, 480);
    m_videoLabel->setAlignment(Qt::AlignCenter);
    m_videoLabel->setScaledContents(false);
    streamingLayout->addWidget(m_videoLabel, 1);

    // Add all widgets to stacked widget
    m_stackedWidget->addWidget(m_tutorialWidget);
    m_stackedWidget->addWidget(m_streamingWidget);

    // Start with tutorial widget
    m_stackedWidget->setCurrentWidget(m_tutorialWidget);

#ifdef __linux__
    m_v4l2_enabled = false; // Disable V4L2 by default
#endif
}

void AirPlayWindow::setupTutorialVideo()
{
    m_tutorialPlayer = new QMediaPlayer(this);
    m_tutorialVideoWidget = new QVideoWidget();
    m_tutorialVideoWidget->setSizePolicy(QSizePolicy::Expanding,
                                         QSizePolicy::Expanding);

    m_tutorialPlayer->setVideoOutput(m_tutorialVideoWidget);
    m_tutorialPlayer->setSource(QUrl("qrc:/resources/airplayer-tutorial.mp4"));
    m_tutorialVideoWidget->setAspectRatioMode(
        Qt::AspectRatioMode::KeepAspectRatioByExpanding);
    m_tutorialVideoWidget->setStyleSheet(
        "QVideoWidget { background-color: transparent; }");
    // Loop the tutorial video
    connect(m_tutorialPlayer, &QMediaPlayer::mediaStatusChanged, this,
            [this](QMediaPlayer::MediaStatus status) {
                if (status == QMediaPlayer::EndOfMedia) {
                    m_tutorialPlayer->setPosition(0);
                    m_tutorialPlayer->play();
                }
            });

    // Auto-play when ready
    connect(m_tutorialPlayer, &QMediaPlayer::mediaStatusChanged, this,
            [this](QMediaPlayer::MediaStatus status) {
                if (status == QMediaPlayer::LoadedMedia) {
                    m_tutorialPlayer->play();
                }
            });
    m_tutorialVideoWidget->setVisible(false);
    m_tutorialLayout->addWidget(m_tutorialVideoWidget, 1);
}

void AirPlayWindow::showTutorialView()
{
    m_stackedWidget->setCurrentWidget(m_tutorialWidget);
    if (m_tutorialPlayer) {
        m_tutorialPlayer->play();
    }
}

void AirPlayWindow::showStreamingView()
{
    m_loadingIndicator->stop();
    m_stackedWidget->setCurrentWidget(m_streamingWidget);
    if (m_tutorialPlayer) {
        m_tutorialPlayer->pause();
    }
}

void AirPlayWindow::startAirPlayServer()
{
    if (m_serverRunning)
        return;

    m_serverThread = new AirPlayServerThread(this);
    connect(m_serverThread, &AirPlayServerThread::statusChanged, this,
            &AirPlayWindow::onServerStatusChanged);
    connect(m_serverThread, &AirPlayServerThread::videoFrameReady, this,
            &AirPlayWindow::updateVideoFrame);
    connect(m_serverThread, &AirPlayServerThread::clientConnectionChanged, this,
            &AirPlayWindow::onClientConnectionChanged);

    m_serverThread->start();
}

void AirPlayWindow::stopAirPlayServer()
{
    if (m_serverThread) {
        m_serverThread->stopServer();
        m_serverThread->wait(3000);
        m_serverThread->deleteLater();
        m_serverThread = nullptr;
    }
    m_serverRunning = false;
}

void AirPlayWindow::updateVideoFrame(QByteArray frameData, int width,
                                     int height)
{
    if (frameData.size() != width * height * 3)
        return;

#ifdef __linux__
    // V4L2 output if enabled
    if (m_v4l2_enabled) {
        writeFrameToV4L2((uint8_t *)frameData.data(), width, height);
        // Show message instead of rendering video when V4L2 is active
        m_videoLabel->setText("Currently being shared via virtual camera");
        return;
    }
#endif

    QImage image((const uchar *)frameData.data(), width, height,
                 QImage::Format_RGB888);
    QPixmap pixmap = QPixmap::fromImage(image);

    // Scale pixmap to fit label while maintaining aspect ratio
    QSize labelSize = m_videoLabel->size();
    QPixmap scaledPixmap =
        pixmap.scaled(labelSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    m_videoLabel->setPixmap(scaledPixmap);
}

void AirPlayWindow::onServerStatusChanged(bool running)
{
    m_serverRunning = running;

    if (running) {
        // Server started successfully, hide loading indicator and show tutorial
        // video
        m_loadingLabel->setText("Waiting for device connection...");

        // Show tutorial video and instructions
        m_tutorialVideoWidget->setVisible(true);
        QLabel *instructionLabel = m_tutorialWidget->findChild<QLabel *>();
        if (instructionLabel && !instructionLabel->text().contains("Follow")) {
            // Find the instruction label (not title or loading label)
            QList<QLabel *> labels = m_tutorialWidget->findChildren<QLabel *>();
            for (QLabel *label : labels) {
                if (label->text().contains("Follow")) {
                    label->setVisible(true);
                    break;
                }
            }
        }

        if (m_tutorialPlayer) {
            m_tutorialPlayer->play();
        }
    }
}

void AirPlayWindow::onClientConnectionChanged(bool connected)
{
    m_clientConnected = connected;
    if (connected) {
        m_loadingLabel->setText("Device connected - receiving stream...");

        showStreamingView();
    } else {
        m_loadingLabel->setText("Waiting for device connection...");
        showTutorialView();
    }
}
#ifdef __linux__

void AirPlayWindow::onV4L2CheckboxToggled(bool enabled)
{
    if (enabled) {
        // Check if V4L2 loopback exists
        if (!checkV4L2LoopbackExists()) {
            // Show message and ask to create V4L2 loopback
            QMessageBox::StandardButton reply = QMessageBox::question(
                this, "V4L2 Loopback Required",
                "Virtual camera device is required for V4L2 output.\n\n"
                "This will create a virtual camera that other applications can "
                "use "
                "to receive the AirPlay stream. The operation requires "
                "administrator privileges.\n\n"
                "Do you want to create the virtual camera device?",
                QMessageBox::Yes | QMessageBox::No, QMessageBox::Yes);

            if (reply == QMessageBox::Yes) {
                if (createV4L2Loopback()) {
                    m_v4l2_enabled = true;

                } else {
                    m_v4l2Checkbox->setChecked(false);
                    m_v4l2_enabled = false;
                    QMessageBox::warning(
                        this, "Error",
                        "Failed to create virtual camera device. Please ensure "
                        "you have the necessary permissions.");
                }
            } else {
                m_v4l2Checkbox->setChecked(false);
                m_v4l2_enabled = false;
            }
        } else {
            m_v4l2_enabled = true;
        }
    } else {
        m_v4l2_enabled = false;
        closeV4L2();
    }
}
#endif

// AirPlayServerThread implementation
AirPlayServerThread::AirPlayServerThread(QObject *parent)
    : QThread(parent), m_shouldStop(false)
{
}

AirPlayServerThread::~AirPlayServerThread()
{
    stopServer();
    wait();
}

void AirPlayServerThread::stopServer()
{
    QMutexLocker locker(&m_mutex);
    m_shouldStop = true;
    m_waitCondition.wakeAll();
}

// Global pointer to current server thread for callbacks
static AirPlayServerThread *g_currentServerThread = nullptr;

// Static callback wrappers for C interface
extern "C" void qt_video_callback(uint8_t *data, int width, int height)
{
    if (g_currentServerThread) {
        QByteArray frameData((const char *)data, width * height * 3);
        emit g_currentServerThread->videoFrameReady(frameData, width, height);
    }
}

extern "C" void qt_connection_callback(bool connected)
{
    if (g_currentServerThread) {
        emit g_currentServerThread->clientConnectionChanged(connected);
    }
}

void AirPlayServerThread::run()
{
    g_currentServerThread = this;
    emit statusChanged(true);

    // Create callbacks structure
    video_renderer_qt_callbacks_t callbacks;
    callbacks.video_callback = qt_video_callback;
    callbacks.connection_callback = qt_connection_callback;

    start_server_qt("iDescriptor", &callbacks);

    // Wait efficiently until stopServer() is called
    QMutexLocker locker(&m_mutex);
    while (!m_shouldStop) {
        m_waitCondition.wait(&m_mutex);
    }

    stop_server_qt();
    g_currentServerThread = nullptr;
    emit statusChanged(false);
}

#ifdef __linux__
// V4L2 Implementation
void AirPlayWindow::initV4L2(int width, int height, const char *device)
{
    closeV4L2(); // Close previous device if any

    m_v4l2_fd = open(device, O_WRONLY);
    if (m_v4l2_fd < 0) {
        qWarning("Failed to open V4L2 device %s: %s", device, strerror(errno));
        return;
    }

    struct v4l2_format fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
    fmt.fmt.pix.width = width;
    fmt.fmt.pix.height = height;
    fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_RGB24;
    fmt.fmt.pix.field = V4L2_FIELD_NONE;
    fmt.fmt.pix.bytesperline = width * 3;
    fmt.fmt.pix.sizeimage = (unsigned int)width * height * 3;

    if (ioctl(m_v4l2_fd, VIDIOC_S_FMT, &fmt) < 0) {
        qWarning("Failed to set V4L2 format: %s", strerror(errno));
        ::close(m_v4l2_fd);
        m_v4l2_fd = -1;
        return;
    }

    m_v4l2_width = width;
    m_v4l2_height = height;
    qDebug("V4L2 device %s initialized to %dx%d", device, width, height);
}

void AirPlayWindow::closeV4L2()
{
    if (m_v4l2_fd >= 0) {
        ::close(m_v4l2_fd);
        m_v4l2_fd = -1;
    }
}

void AirPlayWindow::writeFrameToV4L2(uint8_t *data, int width, int height)
{
    // Check if V4L2 device needs to be initialized or re-initialized
    if (m_v4l2_fd < 0 || m_v4l2_width != width || m_v4l2_height != height) {
        initV4L2(width, height, "/dev/video0"); // Use your v4l2loopback device
    }

    // Write frame to V4L2 device if it's open
    if (m_v4l2_fd >= 0) {
        ssize_t bytes_written =
            write(m_v4l2_fd, data, (size_t)width * height * 3);
        if (bytes_written < 0) {
            qWarning("Failed to write frame to V4L2 device: %s",
                     strerror(errno));
            closeV4L2(); // Close on error to retry initialization
        }
    }
}

bool AirPlayWindow::checkV4L2LoopbackExists()
{
    try {
        QFileInfo videoDevice("/dev/video0");
        return videoDevice.exists();
    } catch (...) {
        qWarning("Exception occurred while checking for V4L2 loopback device");
        return false;
    }
}

bool AirPlayWindow::createV4L2Loopback()
{
    try {
        QProcess process;

        // Use pkexec to run modprobe with administrator privileges
        QStringList arguments;
        arguments << "modprobe" << "v4l2loopback" << "devices=1"
                  << "video_nr=0" << "card_label=\"iDescriptor Virtual Camera\""
                  << "exclusive_caps=1";

        process.start("pkexec", arguments);

        if (!process.waitForStarted(5000)) {
            qWarning("Failed to start pkexec process");
            return false;
        }

        if (!process.waitForFinished(10000)) {
            qWarning("Timeout waiting for modprobe to complete");
            process.kill();
            return false;
        }

        int exitCode = process.exitCode();
        if (exitCode != 0) {
            QString errorOutput = process.readAllStandardError();
            qWarning("modprobe failed with exit code %d: %s", exitCode,
                     errorOutput.toUtf8().constData());
            return false;
        }

        // Wait a bit for the device to be created
        QThread::msleep(500);

        // Verify the device was created
        return checkV4L2LoopbackExists();

    } catch (...) {
        qWarning("Exception occurred while creating V4L2 loopback device");
        return false;
    }
}

void AirPlayWindow::setupV4L2Checkbox()
{
    try {
        m_v4l2Checkbox = new QCheckBox("Enable V4L2 Virtual Camera Output");
        m_v4l2Checkbox->setToolTip("Enable output to virtual camera device "
                                   "that other applications can use");
        m_v4l2Checkbox->setChecked(false);

        connect(m_v4l2Checkbox, &QCheckBox::toggled, this,
                &AirPlayWindow::onV4L2CheckboxToggled);

    } catch (...) {
        qWarning("Exception occurred while setting up V4L2 checkbox");
    }
}
#endif