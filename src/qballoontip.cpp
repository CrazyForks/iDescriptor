#include "qballoontip.h"
#include "iDescriptor.h"
#include <QApplication>
#include <QBasicTimer>
#include <QGraphicsDropShadowEffect>
#include <QGridLayout>
#include <QGuiApplication>
#include <QLabel>
#include <QMouseEvent>
#include <QPainter>
#include <QPropertyAnimation>
#include <QPushButton>
#include <QScreen>
#include <QStyle>
#include <QTimerEvent>
#include <qpainterpath.h>

static QBalloonTip *theSolitaryBalloonTip = nullptr;

void QBalloonTip::showBalloon(const QIcon &icon, const QString &title,
                              const QString &message, QWidget *widget,
                              const QPoint &pos, int timeout, bool showArrow)
{
    hideBalloon();
    if (message.isEmpty() && title.isEmpty())
        return;

    theSolitaryBalloonTip = new QBalloonTip(icon, title, message, widget);
    if (timeout < 0)
        timeout = 10000; // 10 s default
    theSolitaryBalloonTip->balloon(pos, timeout, showArrow);
}

void QBalloonTip::hideBalloon()
{
    if (!theSolitaryBalloonTip)
        return;
    theSolitaryBalloonTip->hide();
    // delete theSolitaryBalloonTip;
    theSolitaryBalloonTip = nullptr;
}

void QBalloonTip::updateBalloonPosition(const QPoint &pos)
{
    if (!theSolitaryBalloonTip)
        return;
    theSolitaryBalloonTip->hide();
    theSolitaryBalloonTip->balloon(pos, 0, theSolitaryBalloonTip->showArrow);
}

bool QBalloonTip::isBalloonVisible() { return theSolitaryBalloonTip; }

QBalloonTip::QBalloonTip(const QIcon &icon, const QString &title,
                         const QString &message, QWidget *widget)
    : QWidget(widget ? widget->window() : QApplication::activeWindow(),
              Qt::ToolTip),
      widget(widget), showArrow(true)
{
    // setAttribute(Qt::WA_DeleteOnClose);
    setAttribute(Qt::WA_TranslucentBackground);
    if (widget) {
        connect(widget, &QWidget::destroyed, this, &QBalloonTip::close);
    } else if (QApplication::activeWindow()) {
        connect(QApplication::activeWindow(), &QWidget::destroyed, this,
                &QBalloonTip::close);
    }

    // Add drop shadow effect
    QGraphicsDropShadowEffect *shadowEffect =
        new QGraphicsDropShadowEffect(this);
    shadowEffect->setBlurRadius(200);
    shadowEffect->setColor(QColor(0, 0, 0, 80));
    shadowEffect->setOffset(0, 5);
    setGraphicsEffect(shadowEffect);

    // QLabel *titleLabel = new QLabel;
    // titleLabel->installEventFilter(this);
    // titleLabel->setText(title);
    // QFont f = titleLabel->font();
    // f.setBold(true);
    // titleLabel->setFont(f);
    // titleLabel->setTextFormat(Qt::PlainText); // to maintain compat with
    // windows

    // const int iconSize = 18;
    // const int closeButtonSize = 15;

    // QPushButton *closeButton = new QPushButton;
    // closeButton->setIcon(style()->standardIcon(QStyle::SP_TitleBarCloseButton));
    // closeButton->setIconSize(QSize(closeButtonSize, closeButtonSize));
    // closeButton->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    // closeButton->setFixedSize(closeButtonSize, closeButtonSize);
    // QObject::connect(closeButton, SIGNAL(clicked()), this, SLOT(close()));

    // QLabel *msgLabel = new QLabel;
    // msgLabel->installEventFilter(this);
    // msgLabel->setText(message);
    // msgLabel->setTextFormat(Qt::PlainText);
    // msgLabel->setAlignment(Qt::AlignTop | Qt::AlignLeft);

    // QGridLayout *layout = new QGridLayout;
    // if (!icon.isNull()) {
    //     QLabel *iconLabel = new QLabel;
    //     iconLabel->setPixmap(
    //         icon.pixmap(QSize(iconSize, iconSize), devicePixelRatio()));
    //     iconLabel->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    //     iconLabel->setMargin(2);
    //     layout->addWidget(iconLabel, 0, 0);
    //     layout->addWidget(titleLabel, 0, 1);
    // } else {
    //     layout->addWidget(titleLabel, 0, 0, 1, 2);
    // }

    // layout->addWidget(closeButton, 0, 2);

    // layout->addWidget(msgLabel, 1, 0, 1, 3);
    // layout->setSizeConstraint(QLayout::SetFixedSize);
    // layout->setContentsMargins(3, 3, 3, 3);
    // setLayout(layout);
}

QBalloonTip::~QBalloonTip() { theSolitaryBalloonTip = nullptr; }

void QBalloonTip::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.drawPixmap(rect(), pixmap);
}

void QBalloonTip::resizeEvent(QResizeEvent *ev) { QWidget::resizeEvent(ev); }

void QBalloonTip::balloon(const QPoint &pos, int msecs, bool showArrow)
{
    this->showArrow = showArrow;
    QScreen *screen = QGuiApplication::screenAt(pos);
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    QRect screenRect = screen->geometry();
    QSize sh = sizeHint();
    const int border = 1;
    const int ah = 18, aw = 18, rc = 7;
    bool arrowAtTop = (pos.y() + sh.height() + ah < screenRect.height());

    setContentsMargins(border + 3, border + (arrowAtTop ? ah : 0) + 2,
                       border + 3, border + (arrowAtTop ? 0 : ah) + 2);
    updateGeometry();
    sh = sizeHint();

    // Center the balloon relative to the pos point (button center)
    int balloonX = pos.x() - sh.width() / 2;

    // Calculate arrow offset from left edge of balloon to center it
    int ao = sh.width() / 2 - aw / 2; // Center the arrow on the balloon

    int ml, mr, mt, mb;
    QSize sz = sizeHint();
    if (!arrowAtTop) {
        ml = mt = 0;
        mr = sz.width() - 1;
        mb = sz.height() - ah - 1;
    } else {
        ml = 0;
        mt = ah;
        mr = sz.width() - 1;
        mb = sz.height() - 1;
    }

    QPainterPath path;
    path.moveTo(ml + rc, mt);
    if (arrowAtTop) {
        if (showArrow) {
            path.lineTo(ml + ao, mt);
            path.lineTo(ml + ao + aw / 2, mt - ah);
            path.lineTo(ml + ao + aw, mt);
        }
        move(qBound(screenRect.left() + 2, balloonX,
                    screenRect.right() - sh.width() - 2),
             pos.y());
    }
    path.lineTo(mr - rc, mt);
    path.arcTo(QRect(mr - rc * 2, mt, rc * 2, rc * 2), 90, -90);
    path.lineTo(mr, mb - rc);
    path.arcTo(QRect(mr - rc * 2, mb - rc * 2, rc * 2, rc * 2), 0, -90);
    if (!arrowAtTop) {
        if (showArrow) {
            path.lineTo(mr - ao - aw, mb);
            path.lineTo(mr - ao - aw / 2, mb + ah);
            path.lineTo(mr - ao, mb);
        }
        move(qBound(screenRect.left() + 2, balloonX,
                    screenRect.right() - sh.width() - 2),
             pos.y() - sh.height());
    }
    path.lineTo(ml + rc, mb);
    path.arcTo(QRect(ml, mb - rc * 2, rc * 2, rc * 2), -90, -90);
    path.lineTo(ml, mt + rc);
    path.arcTo(QRect(ml, mt, rc * 2, rc * 2), 180, -90);

    // Set the mask
    QBitmap bitmap = QBitmap(sizeHint());
    bitmap.fill(Qt::color0);
    QPainter painter1(&bitmap);
    painter1.setPen(QPen(Qt::color1, border));
    painter1.setBrush(QBrush(Qt::color1));
    painter1.drawPath(path);
    setMask(bitmap);

    // Draw the border with background color
    pixmap = QPixmap(sz);
    pixmap.fill(Qt::transparent);
    QPainter painter2(&pixmap);
    painter2.setRenderHint(QPainter::Antialiasing);
    bool isDark = isDarkMode();
    QColor lightColor = qApp->palette().color(QPalette::Light);
    QColor darkColor = qApp->palette().color(QPalette::Dark);
    QColor bgColor = isDark ? lightColor : darkColor;
    painter2.setPen(QPen(bgColor.darker(160), border));
    painter2.setBrush(bgColor);
    painter2.drawPath(path);

    if (msecs > 0)
        timer.start(msecs, this);

    // Install event filter to detect clicks outside
    qApp->installEventFilter(this);

    // Set initial scale and opacity for animation
    setWindowOpacity(0.0);

    // Store the transform origin point (center of the widget)
    QPoint center = rect().center();
    setProperty("transformOriginPoint", center);

    show();

    // Create scale and opacity animations
    QPropertyAnimation *scaleAnim = new QPropertyAnimation(this, "geometry");
    scaleAnim->setDuration(200);
    scaleAnim->setEasingCurve(QEasingCurve::OutBack);

    // Calculate scaled geometry (start from 80% size)
    QRect finalGeometry = geometry();
    QRect startGeometry = finalGeometry;
    int widthDiff = finalGeometry.width() * 0.2;
    int heightDiff = finalGeometry.height() * 0.2;
    startGeometry.adjust(widthDiff / 2, heightDiff / 2, -widthDiff / 2,
                         -heightDiff / 2);

    scaleAnim->setStartValue(startGeometry);
    scaleAnim->setEndValue(finalGeometry);

    QPropertyAnimation *opacityAnim =
        new QPropertyAnimation(this, "windowOpacity");
    opacityAnim->setDuration(200);
    opacityAnim->setStartValue(0.0);
    opacityAnim->setEndValue(1.0);
    opacityAnim->setEasingCurve(QEasingCurve::OutCubic);

    scaleAnim->start(QAbstractAnimation::DeleteWhenStopped);
    opacityAnim->start(QAbstractAnimation::DeleteWhenStopped);
}

void QBalloonTip::mousePressEvent(QMouseEvent *e)
{
    if (e->button() == Qt::LeftButton) {
        emit messageClicked();
    }
}

void QBalloonTip::timerEvent(QTimerEvent *e)
{
    if (e->timerId() == timer.timerId()) {
        timer.stop();
        if (!underMouse())
            close();
        return;
    }
    QWidget::timerEvent(e);
}

bool QBalloonTip::eventFilter(QObject *obj, QEvent *event)
{
    if (event->type() == QEvent::MouseButtonPress) {
        QMouseEvent *mouseEvent = static_cast<QMouseEvent *>(event);
        // Check if click is outside the balloon
        if (!geometry().contains(mouseEvent->globalPos())) {
            close();
            return false;
        }
    } else if (event->type() == QEvent::WindowDeactivate) {
        // Close when window loses focus
        if (obj == this) {
            close();
            return false;
        }
    }
    return QWidget::eventFilter(obj, event);
}

void QBalloonTip::hideEvent(QHideEvent *event)
{
    // Remove event filter when hiding
    qApp->removeEventFilter(this);
    QWidget::hideEvent(event);
}
