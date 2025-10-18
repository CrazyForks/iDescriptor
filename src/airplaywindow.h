#ifndef AIRPLAYWINDOW_H
#define AIRPLAYWINDOW_H

#include "qprocessindicator.h"
#include <QCheckBox>
#include <QCloseEvent>
#include <QLabel>
#include <QMainWindow>
#include <QMediaPlayer>
#include <QMutex>
#include <QStackedWidget>
#include <QThread>
#include <QTimer>
#include <QVBoxLayout>
#include <QVideoWidget>
#include <QWaitCondition>

class AirPlayServerThread : public QThread
{
    Q_OBJECT

public:
    explicit AirPlayServerThread(QObject *parent = nullptr);
    ~AirPlayServerThread() override;

    void stopServer();

signals:
    void statusChanged(bool running);
    void videoFrameReady(QByteArray frameData, int width, int height);
    void clientConnectionChanged(bool connected);

protected:
    void run() override;

private:
    bool m_shouldStop;
    QMutex m_mutex;
    QWaitCondition m_waitCondition;
};

class AirPlayWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit AirPlayWindow(QWidget *parent = nullptr);
    ~AirPlayWindow();

public slots:
    void updateVideoFrame(QByteArray frameData, int width, int height);
    void onClientConnectionChanged(bool connected);

private slots:
    void onServerStatusChanged(bool running);
#ifdef __linux__
    void onV4L2CheckboxToggled(bool enabled);
#endif
private:
    void setupUI();
    void startAirPlayServer();
    void stopAirPlayServer();
    void setupTutorialVideo();
    void showTutorialView();
    void showStreamingView();

    // UI Components
    QStackedWidget *m_stackedWidget;
    QWidget *m_tutorialWidget;
    QWidget *m_streamingWidget;

    QProcessIndicator *m_loadingIndicator;
    QLabel *m_loadingLabel;
    QMediaPlayer *m_tutorialPlayer;
    QVideoWidget *m_tutorialVideoWidget;
    QLabel *m_videoLabel;
    QVBoxLayout *m_tutorialLayout;
    QCheckBox *m_v4l2Checkbox;

    AirPlayServerThread *m_serverThread;
    bool m_serverRunning;
    bool m_clientConnected = false;

#ifdef __linux__
public:
    // V4L2 members - public for C callback access
    int m_v4l2_fd;
    int m_v4l2_width;
    int m_v4l2_height;
    bool m_v4l2_enabled = false;

    // V4L2 methods
    void writeFrameToV4L2(uint8_t *data, int width, int height);

private:
    void initV4L2(int width, int height, const char *device);
    void closeV4L2();
    bool checkV4L2LoopbackExists();
    bool createV4L2Loopback();
    void setupV4L2Checkbox();
#endif
};

#endif // AIRPLAYWINDOW_H
