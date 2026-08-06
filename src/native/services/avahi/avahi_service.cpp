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

#include "avahi_service.h"
#include <QDebug>
#include <QMutexLocker>
#include <avahi-common/error.h>
#include <avahi-common/malloc.h>

AvahiService::AvahiService(QObject *parent)
    : QObject(parent), m_simplePoll(nullptr), m_client(nullptr),
      m_serviceBrowser(nullptr), m_pollTimer(new QTimer(this)), m_running(false)
{
    connect(m_pollTimer, &QTimer::timeout, this, &AvahiService::pollAvahi);
}

AvahiService::~AvahiService() { stopBrowsing(); }

void AvahiService::startBrowsing()
{
    if (m_running || m_starting)
        return;

    qDebug() << "Starting Avahi browsing for Apple devices";
    m_starting = true;
    initializeAvahi();

    if (m_simplePoll && (m_running || m_starting))
        m_pollTimer->start(100); // Poll every 100ms
}

void AvahiService::stopBrowsing()
{
    if (m_running || m_starting || m_simplePoll || m_client || m_serviceBrowser)
        qDebug() << "Stopping Avahi browsing";

    m_running = false;
    m_starting = false;
    m_failurePending = false;
    m_pollTimer->stop();
    cleanupAvahi();
    clearDevices();
}

QMap<QString, NetworkDevice> AvahiService::getNetworkDevices() const
{
    QMutexLocker locker(&m_devicesMutex);
    return m_networkDevices;
}

NetworkDevice
AvahiService::getNetworkDeviceByMac(const QString &macAddress) const
{
    QMutexLocker locker(&m_devicesMutex);
    return m_networkDevices.value(macAddress, NetworkDevice());
}

void AvahiService::pollAvahi()
{
    if (m_simplePoll && (m_running || m_starting)) {
        avahi_simple_poll_iterate(m_simplePoll, 0); // Non-blocking
    }
}

void AvahiService::initializeAvahi()
{
    int error;

    m_simplePoll = avahi_simple_poll_new();
    if (!m_simplePoll) {
        qWarning() << "Failed to create Avahi simple poll";
        scheduleFailure(QStringLiteral("Failed to create Avahi simple poll"));
        return;
    }

    m_client =
        avahi_client_new(avahi_simple_poll_get(m_simplePoll),
                         (AvahiClientFlags)0, clientCallback, this, &error);
    if (!m_client) {
        const QString message = QStringLiteral("Failed to create Avahi client: %1")
                                    .arg(QString::fromUtf8(avahi_strerror(error)));
        qWarning() << message;
        cleanupAvahi();
        scheduleFailure(message);
        return;
    }
}

void AvahiService::clearDevices()
{
    QList<QString> macAddresses;
    {
        QMutexLocker locker(&m_devicesMutex);
        macAddresses = m_networkDevices.keys();
        m_networkDevices.clear();
    }

    for (const QString &macAddress : macAddresses)
        emit deviceRemoved(macAddress);
}

void AvahiService::scheduleFailure(const QString &message)
{
    if (m_failurePending)
        return;

    m_failurePending = true;
    m_failureMessage = message;
    m_running = false;
    m_starting = false;
    m_pollTimer->stop();
    QTimer::singleShot(0, this, &AvahiService::failBrowsing);
}

void AvahiService::failBrowsing()
{
    if (!m_failurePending)
        return;

    m_failurePending = false;
    const QString message = m_failureMessage;
    m_failureMessage.clear();
    m_running = false;
    m_starting = false;
    m_pollTimer->stop();
    cleanupAvahi();
    clearDevices();
    emit failed(message);
}

void AvahiService::cleanupAvahi()
{
    if (m_serviceBrowser) {
        avahi_service_browser_free(m_serviceBrowser);
        m_serviceBrowser = nullptr;
    }

    if (m_client) {
        avahi_client_free(m_client);
        m_client = nullptr;
    }

    if (m_simplePoll) {
        avahi_simple_poll_free(m_simplePoll);
        m_simplePoll = nullptr;
    }
}

void AvahiService::clientCallback(AvahiClient *client, AvahiClientState state,
                                  void *userdata)
{
    AvahiService *service = static_cast<AvahiService *>(userdata);

    if (state == AVAHI_CLIENT_S_RUNNING) {
        qDebug() << "Avahi client running, creating service browser";
        service->m_serviceBrowser = avahi_service_browser_new(
            client, AVAHI_IF_UNSPEC, AVAHI_PROTO_UNSPEC, "_apple-mobdev2._tcp",
            nullptr, (AvahiLookupFlags)0, browseCallback, userdata);

        if (!service->m_serviceBrowser) {
            const QString message =
                QStringLiteral("Failed to create service browser: %1")
                    .arg(QString::fromUtf8(
                        avahi_strerror(avahi_client_errno(client))));
            qWarning() << message;
            service->scheduleFailure(message);
        } else if (service->m_starting) {
            service->m_starting = false;
            service->m_running = true;
            emit service->started();
        }
    } else if (state == AVAHI_CLIENT_FAILURE) {
        const QString message = QStringLiteral("Avahi client failure: %1")
                                    .arg(QString::fromUtf8(
                                        avahi_strerror(avahi_client_errno(client))));
        qWarning() << message;
        service->scheduleFailure(message);
    }
}

void AvahiService::browseCallback(AvahiServiceBrowser *browser,
                                  AvahiIfIndex interface,
                                  AvahiProtocol protocol,
                                  AvahiBrowserEvent event, const char *name,
                                  const char *type, const char *domain,
                                  AvahiLookupResultFlags flags, void *userdata)
{
    Q_UNUSED(browser)
    Q_UNUSED(flags)

    AvahiService *service = static_cast<AvahiService *>(userdata);
    QString macAddress = QString::fromUtf8(name).split('@').first();

    switch (event) {
    case AVAHI_BROWSER_NEW:
        if (!avahi_service_resolver_new(service->m_client, interface, protocol,
                                        name, type, domain, AVAHI_PROTO_UNSPEC,
                                        (AvahiLookupFlags)0, resolveCallback,
                                        userdata)) {
            qWarning() << "Failed to create resolver for" << name;
        }
        break;

    case AVAHI_BROWSER_REMOVE:
        emit service->deviceRemoved(macAddress);

        // Remove from our list
        {
            QMutexLocker locker(&service->m_devicesMutex);
            service->m_networkDevices.remove(macAddress);
        }
        break;

    case AVAHI_BROWSER_FAILURE:
        qWarning() << "Browser failure";
        service->scheduleFailure(QStringLiteral("Avahi service browser failure"));
        break;

    default:
        break;
    }
}

void AvahiService::resolveCallback(
    AvahiServiceResolver *resolver, AvahiIfIndex interface,
    AvahiProtocol protocol, AvahiResolverEvent event, const char *name,
    const char *type, const char *domain, const char *host_name,
    const AvahiAddress *address, uint16_t port, AvahiStringList *txt,
    AvahiLookupResultFlags flags, void *userdata)
{
    Q_UNUSED(interface)
    Q_UNUSED(protocol)
    Q_UNUSED(type)
    Q_UNUSED(domain)
    Q_UNUSED(flags)

    AvahiService *service = static_cast<AvahiService *>(userdata);

    if (event == AVAHI_RESOLVER_FOUND) {
        QString deviceName = QString::fromUtf8(name);

        // Convert address to string
        char addr_str[AVAHI_ADDRESS_STR_MAX];
        avahi_address_snprint(addr_str, sizeof(addr_str), address);

        NetworkDevice device(
            QString::fromUtf8(name), QString::fromUtf8(addr_str),
            deviceName.split('@').first(), QString::fromUtf8(host_name),
            port > 0 ? port : 22);

        // Add to list if not already present
        {
            QMutexLocker locker(&service->m_devicesMutex);
            bool exists = service->m_networkDevices.contains(device.macAddress);
            if (!exists) {
                service->m_networkDevices[device.macAddress] = device;
                emit service->deviceAdded(device);
            }
        }

    } else if (event == AVAHI_RESOLVER_FAILURE) {
        qWarning() << "Failed to resolve service" << name;
    }

    avahi_service_resolver_free(resolver);
}