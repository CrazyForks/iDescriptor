#ifndef DEVICEMANAGERWIDGET_H
#define DEVICEMANAGERWIDGET_H

#include "devicemenuwidget.h"
#include "devicependingwidget.h"
#include "devicesidebarwidget.h"
#include "iDescriptor.h"
#include "recoverydeviceinfowidget.h"
#include <QHBoxLayout>
#include <QMap>
#include <QStackedWidget>
#include <QWidget>

class DeviceManagerWidget : public QWidget
{
    Q_OBJECT

public:
    explicit DeviceManagerWidget(QWidget *parent = nullptr);

    void setCurrentDevice(const std::string &uuid);
    std::string getCurrentDevice() const;

signals:
    void updateNoDevicesConnected();

private slots:
    void onDeviceSelectionChanged(const DeviceSelection &selection);

private:
    void setupUI();

    void addDevice(iDescriptorDevice *device);
    void removeDevice(const std::string &uuid);
    void addRecoveryDevice(const iDescriptorRecoveryDevice *device);
    void removeRecoveryDevice(uint64_t ecid);
    // TODO:udid or uuid ?
    void addPendingDevice(const QString &udid, bool locked);
    void addPairedDevice(iDescriptorDevice *device);
    void removePendingDevice(const QString &udid);

    QHBoxLayout *m_mainLayout;
    DeviceSidebarWidget *m_sidebar;
    QStackedWidget *m_stackedWidget;

    QMap<std::string, std::pair<DeviceMenuWidget *, DeviceSidebarItem *>>
        m_deviceWidgets; // Map to store devices by UDID

    QMap<std::string,
         std::pair<DevicePendingWidget *, DevicePendingSidebarItem *>>
        m_pendingDeviceWidgets; // Map to store devices by UDID

    QMap<uint64_t,
         std::pair<RecoveryDeviceInfoWidget *, RecoveryDeviceSidebarItem *>>
        m_recoveryDeviceWidgets; // Map to store recovery devices by ECID

    std::string m_currentDeviceUuid;
};

#endif // DEVICEMANAGERWIDGET_H