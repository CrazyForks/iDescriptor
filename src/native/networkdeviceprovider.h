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
    enum BrowsingState {
        Loading,
        Started,
        Failed,
    };
    Q_ENUM(BrowsingState)

    Q_PROPERTY(BrowsingState state READ state NOTIFY stateChanged)

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
        connect(m_networkProvider, &AvahiService::started, this,
                &NetworkDeviceProvider::_browsingStarted);
        connect(m_networkProvider, &AvahiService::failed, this,
                &NetworkDeviceProvider::_browsingFailed);
#else
        m_networkProvider = new DnssdService(this);
        connect(m_networkProvider, &DnssdService::deviceAdded, this,
                &NetworkDeviceProvider::_deviceAdded);
        connect(m_networkProvider, &DnssdService::deviceRemoved, this,
                &NetworkDeviceProvider::_deviceRemoved);
        connect(m_networkProvider, &DnssdService::started, this,
                &NetworkDeviceProvider::_browsingStarted);
        connect(m_networkProvider, &DnssdService::failed, this,
                &NetworkDeviceProvider::_browsingFailed);
#endif

        /* Helps main ui load a litte faster */
        QTimer::singleShot(std::chrono::seconds(1), this,
                           [this]() { startBrowsing(true); });
    }

    BrowsingState state() const { return m_state; }

    Q_INVOKABLE void restartBrowsing()
    {
        m_networkProvider->stopBrowsing();
        startBrowsing(true);
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
    BrowsingState m_state = Loading;
    int m_retryBudget = 1;
    quint64 m_browseGeneration = 0;

    void startBrowsing(bool resetRetryBudget)
    {
        if (resetRetryBudget) {
            m_retryBudget = 1;
            ++m_browseGeneration;
        }

        setState(Loading);
        m_networkProvider->startBrowsing();
    }

    void setState(BrowsingState state)
    {
        if (m_state == state)
            return;

        m_state = state;
        emit stateChanged();
    }

    void _browsingStarted()
    {
        setState(Started);
        m_retryBudget = 1;
        emit started();
    }

    void _browsingFailed(const QString &message)
    {
        if (m_retryBudget > 0) {
            --m_retryBudget;
            const quint64 failureGeneration = m_browseGeneration;
            QTimer::singleShot(0, this, [this, failureGeneration]() {
                if (failureGeneration == m_browseGeneration)
                    startBrowsing(false);
            });
            return;
        }

        setState(Failed);
        emit failed(message);
    }

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
    void stateChanged();
    void loadingChanged();
    void startedChanged();
    void started();
    void failed(const QString &message);
    void deviceAdded(const QVariantMap &device);
    void deviceRemoved(const QString &deviceName);
};

#endif // NETWORKDEVICEPROVIDER_H
