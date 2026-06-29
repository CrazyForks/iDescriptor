// Taken from
// https://github.com/gyroflow/gyroflow/blob/master/src/ui_live_reload.cpp
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2021-2022 Adrian <adrian.eddy at gmail>

#include <QDirIterator>
#include <QFileSystemWatcher>
#include <QFileInfo>
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

        const auto roots = engine->rootObjects();
        for (QObject *rootObj : roots) {
            if (!rootObj)
                continue;
            rootObj->setParent(nullptr);
            rootObj->deleteLater();
        }

        engine->clearComponentCache();
        engine->trimComponentCache();
        engine->load(mainPath);

        if (engine->rootObjects().isEmpty())
            qWarning() << "live reload: reload produced no root objects" << mainPath;
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
