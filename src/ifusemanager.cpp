#include "ifusemanager.h"
#include <QDebug>
#include <QProcess>

QStringList iFuseManager::getMountArg(std::string &udid, QString &path)
{
    return QStringList() << "-u" << QString::fromStdString(udid) << path;
}

#ifdef Q_OS_LINUX
QList<QString> iFuseManager::getMountPoints()
{
    QProcess mountProcess;
    mountProcess.start("mount", QStringList() << "-t"
                                              << "fuse.ifuse");
    mountProcess.waitForFinished();

    QString output = mountProcess.readAllStandardOutput();

    if (output.trimmed().isEmpty()) {
        qDebug() << "[iFuseWidget] No existing ifuse mounts found.";
        return {};
    }

    QStringList mountPoints;
    QStringList lines = output.split('\n', Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        // A typical line is: "ifuse on /path/to/mount type fuse.ifuse (...)"
        QString mountPath = line.section(" on ", 1).section(" type ", 0, 0);
        if (!mountPath.isEmpty()) {
            qDebug() << "[iFuseWidget]   - Mount point:" << mountPath;
            mountPoints.append(mountPath);
        }
    }
    return mountPoints;
}
#endif

bool iFuseManager::linuxUnmount(const QString &path)
{
    QProcess umountProcess;
    umountProcess.start("fusermount", QStringList() << "-u" << path);
    umountProcess.waitForFinished();

    if (umountProcess.exitCode() != 0) {
        qWarning() << "[iFuseWidget] Failed to unmount" << path << ":"
                   << umountProcess.readAllStandardError().trimmed();
        return false;
    }

    qDebug() << "[iFuseWidget] Successfully unmounted" << path;
    return true;
}