#ifndef NETWORKDEVICEPROVIDER_H
#define NETWORKDEVICEPROVIDER_H
#include <QObject>
#include <QTimer>

#ifdef __linux__
#include "services/avahi/avahi_service.h"
#else
#include "services/dnssd/dnssd_service.h"
#endif

class NetworkDeviceProvider : public QObject
{
    Q_OBJECT
public:
    static NetworkDeviceProvider *sharedInstance()
    {
        static NetworkDeviceProvider instance;
        return &instance;
    }

    NetworkDeviceProvider(QObject *parent = nullptr) : QObject(parent)
    {
#ifdef __linux__
        m_networkProvider = new AvahiService(this);
        connect(m_networkProvider, &AvahiService::deviceAdded, this,
                &NetworkDeviceProvider::_deviceAdded);
        connect(m_networkProvider, &AvahiService::deviceRemoved, this,
                &NetworkDeviceProvider::_deviceRemoved);
#else
        m_networkProvider = new DnssdService(this);
        connect(m_networkProvider, &DnssdService::deviceAdded, this,
                &NetworkDeviceProvider::_deviceAdded);
        connect(m_networkProvider, &DnssdService::deviceRemoved, this,
                &NetworkDeviceProvider::_deviceRemoved);
#endif

        /* Helps main ui load a litte faster */
        QTimer::singleShot(std::chrono::seconds(1), this,
                           [this]() { m_networkProvider->startBrowsing(); });
    }

    Q_INVOKABLE QMap<QString, QVariant> getNetworkDevices()
    {
        QMap<QString, QVariant> map;

        for (const NetworkDevice &device :
             m_networkProvider->getNetworkDevices()) {
            map[device.macAddress] = device.toVariantMap();
        };

        return map;
    }

    Q_INVOKABLE NetworkDevice getNetworkDeviceByMac(const QString &macAddress)
    {
        return m_networkProvider->getNetworkDeviceByMac(macAddress);
    }

private:
#ifdef __linux__
    AvahiService *m_networkProvider = nullptr;
#else
    DnssdService *m_networkProvider = nullptr;
#endif

    void _deviceRemoved(const QString &deviceName)
    {
        emit deviceRemoved(deviceName);
    };

    void _deviceAdded(const NetworkDevice &device)
    {
        if (device.isValid()) {
            emit deviceAdded(device.toVariantMap());
        } else {
            qDebug() << "Invalid device in networkdeviceprovider:";
        }
    };

signals:
    void deviceAdded(const QVariantMap &device);
    void deviceRemoved(const QString &deviceName);
};

#endif // NETWORKDEVICEPROVIDER_H
