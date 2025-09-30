#ifndef MAINWINDOW_H
#define MAINWINDOW_H
#include "customtabwidget.h"
#include "devicemanagerwidget.h"
#include "devicemenuwidget.h"
#include "iDescriptor.h"
#include "libirecovery.h"
#include <QLabel>
#include <QMainWindow>

QT_BEGIN_NAMESPACE
namespace Ui
{
class MainWindow;
}
QT_END_NAMESPACE

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    static MainWindow *sharedInstance();
    MainWindow(QWidget *parent = nullptr);
    ~MainWindow();
    void onRecoveryDeviceAdded(QObject *recoveryDeviceInfoObj);
    void onRecoveryDeviceRemoved(QObject *deviceInfoObj);

public slots:
    void onDeviceInitFailed(QString udid, lockdownd_error_t err);
    void updateNoDevicesConnected();

private:
    void createMenus();

    Ui::MainWindow *ui;
    CustomTabWidget *m_customTabWidget;
    DeviceManagerWidget *m_deviceManager;
    QStackedWidget *m_mainStackedWidget;
    QLabel *m_connectedDeviceCountLabel;
};
#endif // MAINWINDOW_H
