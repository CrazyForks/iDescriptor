// Taken from
// https://github.com/gyroflow/gyroflow/blob/master/src/ui_live_reload.cpp
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2021-2022 Adrian <adrian.eddy at gmail>

#include <QDirIterator>
#include <QFileSystemWatcher>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>

static void add_watch_paths(QFileSystemWatcher *watcher, const QString &path)
{
    if (!watcher)
        return;

    QFileInfo rootInfo(path);
    if (!rootInfo.exists())
        return;

    if (!watcher->directories().contains(rootInfo.absoluteFilePath()))
        watcher->addPath(rootInfo.absoluteFilePath());

    QDirIterator it(path, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        auto i = it.fileInfo();
        const QString absolutePath = i.absoluteFilePath();
        if (i.isDir()) {
            if (!watcher->directories().contains(absolutePath))
                watcher->addPath(absolutePath);
        } else if (i.isFile()) {
            const QString suffix = i.suffix().toLower();
            if ((suffix == "qml" || suffix == "js" || suffix == "mjs") &&
                !watcher->files().contains(absolutePath)) {
                watcher->addPath(absolutePath);
            }
        }
    }
}

void init_live_reload(QQmlApplicationEngine *engine, const QString &watchPath,
                      const QString &entryPath)
{
    if (!engine) {
        qWarning() << "live reload: engine is null";
        return;
    }

    QFileInfo entryInfo(entryPath);
    if (!entryInfo.exists()) {
        qWarning() << "live reload: entry does not exist" << entryPath;
        return;
    }

    QFileSystemWatcher *w = new QFileSystemWatcher(engine);
    add_watch_paths(w, watchPath);

    const QUrl mainPath = QUrl::fromLocalFile(entryInfo.absoluteFilePath());

    qDebug() << "live reload: watching" << watchPath << "entry" << mainPath;

    QString prevFile = "";
    QTimer *reloadTimer = new QTimer(engine);
    reloadTimer->setSingleShot(true);
    reloadTimer->setInterval(180);

    QObject::connect(reloadTimer, &QTimer::timeout, engine, [=]() mutable {
        prevFile.clear();
        add_watch_paths(w, watchPath);

        const bool quitOnLastWindowClosed = QGuiApplication::quitOnLastWindowClosed();
        QGuiApplication::setQuitOnLastWindowClosed(false);

        const auto roots = engine->rootObjects();
        for (QObject *rootObj : roots) {
            if (!rootObj)
                continue;

            if (rootObj->metaObject()->indexOfMethod("prepareLiveReload()") >= 0) {
                QMetaObject::invokeMethod(rootObj, "prepareLiveReload",
                                          Qt::DirectConnection);
            }

            rootObj->setParent(nullptr);
            rootObj->deleteLater();
        }

        qDebug() << "live reload: teardown scheduled"
                 << "roots" << roots.size();

        // Let FluentUI's native frameless windows and the launcher process their
        // DeferredDelete events naturally. Forcing them through sendPostedEvents()
        // here can destroy Windows event-filter objects reentrantly.
        QTimer::singleShot(100, engine, [engine, mainPath, quitOnLastWindowClosed]() {
            qDebug() << "live reload: teardown complete"
                     << "roots" << engine->rootObjects().size()
                     << "windows" << QGuiApplication::allWindows().size();

            // Keep QML singleton instances alive so external singleton services
            // such as FluentUI do not retain references to deleted instances.
            engine->clearComponentCache();
            engine->load(mainPath);
            QGuiApplication::setQuitOnLastWindowClosed(quitOnLastWindowClosed);

            qDebug() << "live reload: loaded" << mainPath
                     << "roots" << engine->rootObjects().size();
            if (engine->rootObjects().isEmpty())
                qWarning() << "live reload: reload produced no root objects" << mainPath;
        });
    });

    auto scheduleReload = [=](const QString &path) mutable {
        if (prevFile == path && reloadTimer->isActive())
            return;

        prevFile = path;
        qDebug() << "live reload: change" << path;
        if (QFileInfo::exists(path) && !w->files().contains(path) &&
            !w->directories().contains(path)) {
            w->addPath(path);
        }
        reloadTimer->start();
    };

    QObject::connect(w, &QFileSystemWatcher::fileChanged, engine, scheduleReload);
    QObject::connect(w, &QFileSystemWatcher::directoryChanged, engine,
                     [=](const QString &path) mutable {
                         add_watch_paths(w, watchPath);
                         scheduleReload(path);
                     });
}
