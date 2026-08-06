#ifndef SYSTEMAPPEARANCE_H
#define SYSTEMAPPEARANCE_H

#include <QObject>

#ifdef Q_OS_LINUX
#include <QDBusVariant>

class QDBusServiceWatcher;
#endif

class SystemAppearance : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY darkModeChanged)
    Q_PROPERTY(int portalColorScheme READ portalColorScheme NOTIFY portalColorSchemeChanged)
    Q_PROPERTY(bool portalAvailable READ portalAvailable NOTIFY portalAvailableChanged)

public:
    explicit SystemAppearance(QObject *parent = nullptr);

    bool darkMode() const;
    int portalColorScheme() const;
    bool portalAvailable() const;

signals:
    void darkModeChanged();
    void portalColorSchemeChanged();
    void portalAvailableChanged();

private:
    bool detectQtDarkMode() const;
    void updateDarkMode();
    void setPortalAvailable(bool available);
    void setPortalColorScheme(int colorScheme);

#ifdef Q_OS_LINUX
    void initializePortal();
    void refreshPortalColorScheme();
    void clearPortalState();

private slots:
    void onPortalSettingChanged(const QString &nameSpace, const QString &key,
                                const QDBusVariant &value);
#endif

private:
    bool m_darkMode = false;
    int m_portalColorScheme = 0;
    bool m_portalAvailable = false;

#ifdef Q_OS_LINUX
    QDBusServiceWatcher *m_portalWatcher = nullptr;
#endif
};

#endif // SYSTEMAPPEARANCE_H
