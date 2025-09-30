#include "customtabwidget.h"
#include <QEasingCurve>
#include <QGraphicsDropShadowEffect>
#include <QMainWindow>
#include <QPainter>
#include <QStyleOption>
#include <QTimer>

// CustomTab implementation
CustomTab::CustomTab(const QString &text, QWidget *parent)
    : QPushButton(text, parent), m_notificationLabel(nullptr),
      m_notificationCount(0)
{
    setCheckable(true);
    setFixedHeight(54);
    setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Fixed);

    // Set up notification label
    m_notificationLabel = new QLabel(this);
    m_notificationLabel->setAlignment(Qt::AlignCenter);
    m_notificationLabel->hide();
    m_notificationLabel->setStyleSheet("QLabel {"
                                       "  background-color: #e6eef9;"
                                       "  border-radius: 16px;"
                                       "  color: #333;"
                                       "  font-weight: 500;"
                                       "  min-width: 32px;"
                                       "  min-height: 32px;"
                                       "  max-width: 32px;"
                                       "  max-height: 32px;"
                                       "}");

    updateNotificationDisplay();
}

void CustomTab::setNotificationCount(int count)
{
    m_notificationCount = count;
    updateNotificationDisplay();
}

void CustomTab::setIcon(const QIcon &icon)
{
    QPushButton::setIcon(icon);
    setIconSize(QSize(20, 20));
}

void CustomTab::updateNotificationDisplay()
{
    if (m_notificationCount > 0) {
        m_notificationLabel->setText(QString::number(m_notificationCount));
        m_notificationLabel->show();

        // Position notification label to the right of the text
        QFontMetrics fm(font());
        int textWidth = fm.horizontalAdvance(text());
        int iconWidth = iconSize().width();
        int totalContentWidth = (iconWidth > 0 ? iconWidth + 8 : 0) + textWidth;

        int x = (width() - totalContentWidth) / 2 + totalContentWidth + 12;
        int y = (height() - 32) / 2;

        m_notificationLabel->setGeometry(x, y, 32, 32);
    } else {
        m_notificationLabel->hide();
    }
}

void CustomTab::paintEvent(QPaintEvent *event)
{
    QPushButton::paintEvent(event);
    updateNotificationDisplay();

    // Update notification label style based on checked state
    if (isChecked()) {
        m_notificationLabel->setStyleSheet("QLabel {"
                                           "  background-color: #185ee0;"
                                           "  border-radius: 16px;"
                                           "  color: white;"
                                           "  font-weight: 500;"
                                           "  min-width: 32px;"
                                           "  min-height: 32px;"
                                           "  max-width: 32px;"
                                           "  max-height: 32px;"
                                           "}");
    } else {
        m_notificationLabel->setStyleSheet("QLabel {"
                                           "  background-color: #e6eef9;"
                                           "  border-radius: 16px;"
                                           "  color: #333;"
                                           "  font-weight: 500;"
                                           "  min-width: 32px;"
                                           "  min-height: 32px;"
                                           "  max-width: 32px;"
                                           "  max-height: 32px;"
                                           "}");
    }
}

// CustomTabWidget implementation
CustomTabWidget::CustomTabWidget(QWidget *parent)
    : QWidget(parent), m_currentIndex(0)
{
    m_mainLayout = new QVBoxLayout(this);
    m_mainLayout->setContentsMargins(0, 0, 0, 0);
    m_mainLayout->setSpacing(0);

    // Create tab bar container
    m_tabBar = new QWidget();
    m_tabBar->setFixedHeight(70); // 54px height + 16px padding
    m_tabLayout = new QHBoxLayout(m_tabBar);
    // m_tabLayout->setContentsMargins(12, 8, 12, 8);
    m_tabLayout->setSpacing(0);

    // Style the tab bar
    m_tabBar->setStyleSheet("QWidget {"
                            // "  background-color: white;"
                            "  border-radius: 35px;"
                            "}");

    // Add drop shadow effect
    QGraphicsDropShadowEffect *shadow = new QGraphicsDropShadowEffect();
    shadow->setBlurRadius(20);
    shadow->setColor(QColor(24, 94, 224, 38)); // rgba(24, 94, 224, 0.15)
    shadow->setOffset(0, 6);
    m_tabBar->setGraphicsEffect(shadow);

    m_buttonGroup = new QButtonGroup(this);
    m_buttonGroup->setExclusive(true);

    // Create stacked widget for content
    m_stackedWidget = new QStackedWidget();

    // Add widgets to layout
    m_mainLayout->addWidget(m_tabBar);
    m_mainLayout->addWidget(m_stackedWidget, 1);

    setupGlider();
}

void CustomTabWidget::setupGlider()
{
    m_glider = new QWidget(m_tabBar);
    m_glider->setStyleSheet("QWidget {"
                            "  background-color: #185ee0;"
                            "  border-radius: 1px;"
                            "}");
    // Set initial size - will be updated in animateGlider
    m_glider->setFixedSize(100, 2); // 2px height for bottom border effect
    m_glider->lower();              // Make sure glider is behind tabs

    m_gliderAnimation = new QPropertyAnimation(m_glider, "pos");
    m_gliderAnimation->setDuration(250);
    m_gliderAnimation->setEasingCurve(QEasingCurve::OutCubic);
}

int CustomTabWidget::addTab(QWidget *widget, const QString &label)
{
    return addTab(widget, QIcon(), label);
}

int CustomTabWidget::addTab(QWidget *widget, const QIcon &icon,
                            const QString &label)
{
    CustomTab *tab = new CustomTab(label, m_tabBar);
    if (!icon.isNull()) {
        tab->setIcon(icon);
    }
    connect(tab, &CustomTab::clicked, this, &CustomTabWidget::onTabClicked);
    int index = m_tabs.count();
    m_tabs.append(tab);
    m_widgets.append(widget);

    m_tabLayout->addWidget(tab);
    m_stackedWidget->addWidget(widget);
    m_buttonGroup->addButton(tab, index);

    // Set first tab as checked by default
    if (index == 0) {
        tab->setChecked(true);
    }

    return index;
}

void CustomTabWidget::setCurrentIndex(int index)
{
    if (index < 0 || index >= m_tabs.count() || index == m_currentIndex) {
        return;
    }

    m_currentIndex = index;
    m_tabs[index]->setChecked(true);
    m_stackedWidget->setCurrentIndex(index);
    updateTabStyles();
    animateGlider(index);

    emit currentChanged(index);
}

void CustomTabWidget::finalizeStyles()
{
    updateTabStyles();
    // Position glider for first tab
    QTimer::singleShot(0, [this]() { animateGlider(0); });
}

int CustomTabWidget::currentIndex() const { return m_currentIndex; }

QWidget *CustomTabWidget::widget(int index) const
{
    if (index < 0 || index >= m_widgets.count()) {
        return nullptr;
    }
    return m_widgets[index];
}

void CustomTabWidget::setTabNotification(int index, int count)
{
    if (index >= 0 && index < m_tabs.count()) {
        m_tabs[index]->setNotificationCount(count);
    }
}

void CustomTabWidget::onTabClicked()
{
    CustomTab *clickedTab = qobject_cast<CustomTab *>(sender());
    if (!clickedTab)
        return;

    int index = m_tabs.indexOf(clickedTab);
    if (index != -1) {
        setCurrentIndex(index);
    }
}

void CustomTabWidget::animateGlider(int index)
{
    if (index < 0 || index >= m_tabs.count())
        return;

    CustomTab *targetTab = m_tabs[index];
    if (!targetTab)
        return;

    // Get the actual position and size of the target tab
    QPoint targetTabPos = targetTab->pos();
    QSize targetTabSize = targetTab->size();

    // Set glider width to match tab width and height to 2px for bottom border
    m_glider->setFixedSize(targetTabSize.width(), 2);

    // Position glider at the bottom of the target tab
    int targetX = targetTabPos.x();
    int targetY =
        targetTabPos.y() + targetTabSize.height() - 2; // Position at bottom

    m_gliderAnimation->stop();
    m_gliderAnimation->setStartValue(m_glider->pos());
    m_gliderAnimation->setEndValue(QPoint(targetX, targetY));
    m_gliderAnimation->start();
}

void CustomTabWidget::updateTabStyles()
{
    for (int i = 0; i < m_tabs.count(); ++i) {
        CustomTab *tab = m_tabs[i];
        if (tab->isChecked()) {
            tab->setStyleSheet("CustomTab {"
                               "  color: #185ee0;"
                               "  font-weight: 500;"
                               "  font-size: 20px;"
                               "  border: none;"
                               "  outline: none;"
                               "  border-radius: 27px;"
                               "  background-color: transparent;"
                               "}"
                               "CustomTab:hover {"
                               "  background-color: transparent;"
                               "}");
        } else {
            tab->setStyleSheet("CustomTab {"
                               "  color: #666;"
                               "  font-weight: 500;"
                               "  font-size: 20px;"
                               "  border: none;"
                               "  outline: none;"
                               "  border-radius: 27px;"
                               "  background-color: transparent;"
                               "}"
                               "CustomTab:hover {"
                               "  color: #185ee0;"
                               "  background-color: transparent;"
                               "}");
        }
    }
}

void CustomTabWidget::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);

    // Update glider position when widget is resized
    if (m_currentIndex >= 0 && m_currentIndex < m_tabs.count()) {
        // Use a timer to ensure layout has been updated
        QTimer::singleShot(0, [this]() { animateGlider(m_currentIndex); });
    }
}

// #ifdef Q_OS_MAC
// void CustomTabWidget::ensureTitlebarIntegration()
// {
//     // Ensure the tab bar maintains the correct height and margins for
//     titlebar integration m_tabBar->setFixedHeight(98); // 70px + 28px
//     titlebar height m_tabLayout->setContentsMargins(12, 36, 12, 8); // Add
//     top margin for titlebar

//     // Ensure the parent window attribute is maintained
//     if (QMainWindow *mainWindow = qobject_cast<QMainWindow*>(window())) {
//         mainWindow->setAttribute(Qt::WA_ContentsMarginsRespectsSafeArea,
//         false);
//     }

//     // Update glider position after titlebar integration changes
//     if (m_currentIndex >= 0 && m_currentIndex < m_tabs.count()) {
//         QTimer::singleShot(0, [this]() {
//             animateGlider(m_currentIndex);
//         });
//     }
// }
// #endif