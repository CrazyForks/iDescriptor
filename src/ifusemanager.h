#ifndef IFUSEMANAGER_H
#define IFUSEMANAGER_H

#include <QObject>

class iFuseManager : public QObject
{
    Q_OBJECT
public:
    // explicit iFuseManager(QObject *parent = nullptr);
    static QList<QString> getMountPoints();
#ifdef Q_OS_LINUX
    static QStringList getMountArg(std::string &udid, QString &path);
#endif
    // TODO: need to implement a cross-platform mount and unmount function
    static bool linuxUnmount(const QString &path);
signals:
};

#endif // IFUSEMANAGER_H
