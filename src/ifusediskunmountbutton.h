#ifndef IFUSEDISKUNMOUNTBUTTON_H
#define IFUSEDISKUNMOUNTBUTTON_H

#include <QPushButton>

class iFuseDiskUnmountButton : public QPushButton
{
    Q_OBJECT
public:
    explicit iFuseDiskUnmountButton(const QString &path,
                                    QWidget *parent = nullptr);

signals:
};

#endif // IFUSEDISKUNMOUNTBUTTON_H
