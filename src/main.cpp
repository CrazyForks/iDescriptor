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

#include "constants.h"
#include "iDescriptor.h"
#include "settingsmanager.h"
#include <QApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QMessageBox>
#include <QStyleFactory>
#include <QtGlobal>
#include <stdlib.h>
#ifdef WIN32
#include "platform/windows/win_common.h"
#endif
#include "networkdeviceprovider.h"
// #include "thumbnailmodel.h"
#include "thumbnailprovider.h"
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>
#define FLUENTUI_BUILD_STATIC_LIB 1

int main(int argc, char *argv[])
{
#ifdef WIN32
    // ::SetUnhandledExceptionFilter(MyUnhandledExceptionFilter);
    qputenv("QT_QPA_PLATFORM", "windows:darkmode=2");
#endif
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
#else
    qputenv("QT_QUICK_CONTROLS_STYLE", "Default");
#endif
#ifdef Q_OS_LINUX
    // fix bug UOSv20 v-sync does not work
    qputenv("QSG_RENDER_LOOP", "basic");
#endif

#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
#endif
#if (QT_VERSION < QT_VERSION_CHECK(6, 0, 0))
    QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QApplication::setAttribute(Qt::AA_UseHighDpiPixmaps);
#if (QT_VERSION >= QT_VERSION_CHECK(5, 14, 0))
    QApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
#endif
#endif

    QApplication a(argc, argv);
    QCoreApplication::setOrganizationName("iDescriptor");
    QCoreApplication::setApplicationName("iDescriptor");
    QCoreApplication::setApplicationVersion(APP_VERSION);
    if (a.arguments().contains("--reset-settings")) {
        // SettingsManager::sharedInstance()->clear();
        QMessageBox::information(nullptr, "Settings Reset",
                                 "All application settings have been reset to "
                                 "their default values.");
    }
    QQmlApplicationEngine engine;

#ifdef WIN32

    QString appPath = QCoreApplication::applicationDirPath();
    QString gstPluginPath =
        QDir::toNativeSeparators(appPath + "/gstreamer-1.0");
    QString gstPluginScannerPath = QDir::toNativeSeparators(
        appPath + "/gstreamer-1.0/libexec/gst-plugin-scanner.exe");

    const char *oldPath = getenv("PATH");
    QString newPath = appPath + ";" + QString(oldPath);
    qputenv("PATH", newPath.toUtf8());

    qputenv("GST_PLUGIN_PATH", gstPluginPath.toUtf8());
    qDebug() << "GST_PLUGIN_PATH=" << gstPluginPath;
    qputenv("GST_REGISTRY_REUSE_PLUGIN_SCANNER", "no");
    qDebug() << "GST_REGISTRY_REUSE_PLUGIN_SCANNER=no";
    qputenv("GST_PLUGIN_SYSTEM_PATH", gstPluginPath.toUtf8());
    qDebug() << "GST_PLUGIN_SYSTEM_PATH=" << gstPluginPath;
    qputenv("GST_DEBUG", "GST_PLUGIN_LOADING:5");
    qDebug() << "GST_DEBUG=GST_PLUGIN_LOADING:5";
    qputenv("GST_PLUGIN_SCANNER_1_0", gstPluginScannerPath.toUtf8());
    qDebug() << "GST_PLUGIN_SCANNER_1_0=" << gstPluginScannerPath;
#endif
#ifdef __APPLE__
    QString appPath = QCoreApplication::applicationDirPath();
    QString frameworksPath =
        QDir::toNativeSeparators(appPath + "/../Frameworks");
    QString gstPluginPath =
        QDir::toNativeSeparators(frameworksPath + "/gstreamer");
    QString gstPluginScannerPath =
        QDir::toNativeSeparators(frameworksPath + "/gst-plugin-scanner");

    setenv("GST_PLUGIN_PATH", gstPluginPath.toUtf8().constData(), 1);
    setenv("GST_PLUGIN_SYSTEM_PATH", gstPluginPath.toUtf8().constData(), 1);
    setenv("GST_PLUGIN_SCANNER", gstPluginScannerPath.toUtf8().constData(), 1);
#endif

    const QUrl url(QStringLiteral("qrc:/src/qml/Main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &a,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);

// FIXME: for some reason we have to set this
// dont let this end up in final build
#ifdef WIN32
    engine.addImportPath("C:/Qt/6.8.3/mingw_64/qml");
#endif
    Constants constants;
    // qmlRegisterType<ThumbnailModel>("iDescriptor", 1, 0, "ThumbnailModel");
    engine.rootContext()->setContextProperty("CONSTANTS", &constants);
    engine.addImageProvider("thumb", ThumbnailProvider::sharedInstance());
    engine.rootContext()->setContextProperty(
        "ThumbnailProvider", ThumbnailProvider::sharedInstance());
    engine.rootContext()->setContextProperty(
        "NetworkDeviceProvider", NetworkDeviceProvider::sharedInstance());
    engine.load(url);

    return a.exec();
}
