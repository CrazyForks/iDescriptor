#ifndef CONSTANTS_H
#define CONSTANTS_H

#include "iDescriptor.h"
#include <QObject>

class Constants : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString REPO_URL READ REPO_URL CONSTANT)
public:
    explicit Constants(QObject *parent = nullptr) : QObject(parent) {}

    QString REPO_URL() const { return QStringLiteral(IDESCRIPTOR_REPO_URL); }
};

#endif // CONSTANTS_H
