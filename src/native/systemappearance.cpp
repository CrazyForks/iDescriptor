#include "systemappearance.h"

#include <QGuiApplication>
#include <QPalette>
#include <QStyleHints>

#ifdef Q_OS_LINUX
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QVariant>
#endif

namespace {
#ifdef Q_OS_LINUX
constexpr auto PORTAL_SERVICE = "org.freedesktop.portal.Desktop";
constexpr auto PORTAL_PATH = "/org/freedesktop/portal/desktop";
constexpr auto PORTAL_SETTINGS_INTERFACE = "org.freedesktop.portal.Settings";
constexpr auto APPEARANCE_NAMESPACE = "org.freedesktop.appearance";
constexpr auto COLOR_SCHEME_KEY = "color-scheme";

int portalColorSchemeFromVariant(QVariant value)
{
    while (value.canConvert<QDBusVariant>()) {
        value = value.value<QDBusVariant>().variant();
    }

    bool ok = false;
    const uint colorScheme = value.toUInt(&ok);
    if (!ok || colorScheme > 2) {
        return 0;
    }
    return static_cast<int>(colorScheme);
}
#endif
} // namespace

SystemAppearance::SystemAppearance(QObject *parent) : QObject(parent)
{
    if (auto *application = qobject_cast<QGuiApplication *>(QCoreApplication::instance())) {
        connect(application->styleHints(), &QStyleHints::colorSchemeChanged,
                this, [this]() { updateDarkMode(); });
        connect(application, &QGuiApplication::paletteChanged,
                this, [this]() { updateDarkMode(); });
    }

#ifdef Q_OS_LINUX
    initializePortal();
#endif
    updateDarkMode();
}

bool SystemAppearance::darkMode() const
{
    return m_darkMode;
}

int SystemAppearance::portalColorScheme() const
{
    return m_portalColorScheme;
}

bool SystemAppearance::portalAvailable() const
{
    return m_portalAvailable;
}

bool SystemAppearance::detectQtDarkMode() const
{
    if (const auto *application = qobject_cast<QGuiApplication *>(QCoreApplication::instance())) {
        const Qt::ColorScheme colorScheme = application->styleHints()->colorScheme();
        if (colorScheme != Qt::ColorScheme::Unknown) {
            return colorScheme == Qt::ColorScheme::Dark;
        }

        const QPalette palette = application->palette();
        return palette.color(QPalette::WindowText).lightnessF()
            > palette.color(QPalette::Window).lightnessF();
    }
    return false;
}

void SystemAppearance::updateDarkMode()
{
    const bool darkMode = m_portalColorScheme == 1
        ? true
        : m_portalColorScheme == 2 ? false : detectQtDarkMode();

    if (m_darkMode == darkMode) {
        return;
    }

    m_darkMode = darkMode;
    emit darkModeChanged();
}

void SystemAppearance::setPortalAvailable(bool available)
{
    if (m_portalAvailable == available) {
        return;
    }

    m_portalAvailable = available;
    emit portalAvailableChanged();
}

void SystemAppearance::setPortalColorScheme(int colorScheme)
{
    if (colorScheme < 0 || colorScheme > 2) {
        colorScheme = 0;
    }
    if (m_portalColorScheme == colorScheme) {
        return;
    }

    m_portalColorScheme = colorScheme;
    emit portalColorSchemeChanged();
    updateDarkMode();
}

#ifdef Q_OS_LINUX
void SystemAppearance::initializePortal()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        clearPortalState();
        return;
    }

    bus.connect(QString::fromLatin1(PORTAL_SERVICE),
                QString::fromLatin1(PORTAL_PATH),
                QString::fromLatin1(PORTAL_SETTINGS_INTERFACE),
                QStringLiteral("SettingChanged"), this,
                SLOT(onPortalSettingChanged(QString,QString,QDBusVariant)));

    m_portalWatcher = new QDBusServiceWatcher(
        QString::fromLatin1(PORTAL_SERVICE), bus,
        QDBusServiceWatcher::WatchForRegistration
            | QDBusServiceWatcher::WatchForUnregistration,
        this);

    connect(m_portalWatcher, &QDBusServiceWatcher::serviceRegistered,
            this, [this]() { refreshPortalColorScheme(); });
    connect(m_portalWatcher, &QDBusServiceWatcher::serviceUnregistered,
            this, [this]() { clearPortalState(); });

    refreshPortalColorScheme();
}

void SystemAppearance::refreshPortalColorScheme()
{
    QDBusInterface portal(QString::fromLatin1(PORTAL_SERVICE),
                          QString::fromLatin1(PORTAL_PATH),
                          QString::fromLatin1(PORTAL_SETTINGS_INTERFACE),
                          QDBusConnection::sessionBus());
    if (!portal.isValid()) {
        clearPortalState();
        return;
    }

    const QDBusMessage reply = portal.call(
        QStringLiteral("Read"), QString::fromLatin1(APPEARANCE_NAMESPACE),
        QString::fromLatin1(COLOR_SCHEME_KEY));
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
        clearPortalState();
        return;
    }

    setPortalAvailable(true);
    setPortalColorScheme(portalColorSchemeFromVariant(reply.arguments().constFirst()));
}

void SystemAppearance::clearPortalState()
{
    setPortalAvailable(false);
    setPortalColorScheme(0);
    updateDarkMode();
}

void SystemAppearance::onPortalSettingChanged(const QString &nameSpace,
                                               const QString &key,
                                               const QDBusVariant &value)
{
    if (nameSpace != QString::fromLatin1(APPEARANCE_NAMESPACE)
        || key != QString::fromLatin1(COLOR_SCHEME_KEY)) {
        return;
    }

    setPortalAvailable(true);
    setPortalColorScheme(portalColorSchemeFromVariant(value.variant()));
}
#endif
