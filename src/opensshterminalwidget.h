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

#ifndef OPENSSHTERMINALWIDGET_H
#define OPENSSHTERMINALWIDGET_H

#include <QWidget>
#ifdef __linux__
#include "core/services/avahi/avahi_service.h"
#else
#include "core/services/dnssd/dnssd_service.h"
#endif

#include "iDescriptor.h"
#include "sshterminalwidget.h"
#include <QAbstractButton>
#include <QButtonGroup>
#include <QGroupBox>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QWidget>

enum class DeviceType { None, Wired, Wireless };

class OpenSSHTerminalWidget : public QWidget
{
    Q_OBJECT
public:
    explicit OpenSSHTerminalWidget(QWidget *parent = nullptr);
    ~OpenSSHTerminalWidget();
private slots:
    void onOpenSSHTerminal();
    void onWiredDeviceAdded(const iDescriptorDevice *device);
    void onWiredDeviceRemoved(const std::string &udid);
    void onWirelessDeviceAdded(const NetworkDevice &device);
    void onWirelessDeviceRemoved(const QString &deviceName);
    void onDeviceSelected(QAbstractButton *button);

private:
    void setupDeviceSelectionUI(QVBoxLayout *layout);
    void updateDeviceList();
    void clearDeviceButtons();
    void addWiredDevice(const iDescriptorDevice *device);
    void addWirelessDevice(const NetworkDevice &device);
    void resetSelection();

    QLabel *m_infoLabel;
    QPushButton *m_connectButton;

    // Device selection UI
    QVBoxLayout *m_deviceLayout;
    QGroupBox *m_wiredDevicesGroup;
    QGroupBox *m_wirelessDevicesGroup;
    QVBoxLayout *m_wiredDevicesLayout;
    QVBoxLayout *m_wirelessDevicesLayout;
    QButtonGroup *m_deviceButtonGroup;

#ifdef __linux__
    AvahiService *m_wirelessProvider = nullptr;
#else
    DnssdService *m_wirelessProvider = nullptr;
#endif

    DeviceType m_selectedDeviceType = DeviceType::None;
    iDescriptorDevice *m_selectedWiredDevice = nullptr;
    NetworkDevice m_selectedNetworkDevice;

    const iDescriptorDevice *m_device = nullptr;

    // SSH components
    ssh_session m_sshSession;
    ssh_channel m_sshChannel;
    QTimer *m_sshTimer;
    QProcess *iproxyProcess = nullptr;

    bool m_sshConnected = false;
    bool m_isInitialized = false;
signals:
};

#endif // OPENSSHTERMINALWIDGET_H
