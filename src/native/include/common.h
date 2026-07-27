#include <QString>
#include <QVariantMap>

struct NetworkDevice {
    QString name;       // service name
    QString hostname;   // e.g., iPhone-2.local
    QString address;    // IPv4 or IPv6 address
    uint16_t port = 22; // SSH port
    QString macAddress; // MAC address if available

    NetworkDevice() = default;
    NetworkDevice(const QString &name, const QString &address,
                  const QString &macAddress, const QString &hostname,
                  uint16_t port)
        : name(name), hostname(hostname), address(address), port(port),
          macAddress(macAddress)
    {
    }

    bool isValid() const
    {
        return !name.isEmpty() && !address.isEmpty() && !macAddress.isEmpty();
    }

    bool operator==(const NetworkDevice &other) const
    {
        return name == other.name && address == other.address;
    }

    QVariantMap toVariantMap() const
    {
        QVariantMap map;
        map["name"] = name;
        map["address"] = address;
        map["port"] = port;
        map["macAddress"] = macAddress;
        map["hostname"] = hostname;
        return map;
    }
};
