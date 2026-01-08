#ifndef QBALLOONTIP_H
#define QBALLOONTIP_H

#include <QBasicTimer>
#include <QIcon>
#include <QSystemTrayIcon>
#include <QWidget>

class QBalloonTip : public QWidget
{
    Q_OBJECT
public:
    explicit QBalloonTip(const QIcon &icon, const QString &title,
                         const QString &msg, QWidget *widget);
    void hideBalloon();
    bool isBalloonVisible();
    void updateBalloonPosition(const QPoint &pos);
    void showBalloon(const QIcon &icon, const QString &title,
                     const QString &msg, QWidget *widget, const QPoint &pos,
                     int timeout, bool showArrow = true);
    void balloon(const QPoint &, int, bool);

signals:
    void messageClicked();

protected:
    ~QBalloonTip();
    void paintEvent(QPaintEvent *) override;
    void resizeEvent(QResizeEvent *) override;
    void mousePressEvent(QMouseEvent *e) override;
    void timerEvent(QTimerEvent *e) override;
    bool eventFilter(QObject *obj, QEvent *event) override;
    void hideEvent(QHideEvent *event) override;

private:
    QWidget *widget;
    QPixmap pixmap;
    QBasicTimer timer;
    bool showArrow;
};
#endif // QBALLOONTIP_H