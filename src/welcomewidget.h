#ifndef WELCOMEWIDGET_H
#define WELCOMEWIDGET_H

#include "responsiveqlabel.h"
#include <QHBoxLayout>
#include <QLabel>
#include <QPixmap>
#include <QVBoxLayout>
#include <QWidget>

class WelcomeWidget : public QWidget
{
    Q_OBJECT

public:
    explicit WelcomeWidget(QWidget *parent = nullptr);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void setupUI();
    QLabel *createStyledLabel(const QString &text, int fontSize = 0,
                              bool isBold = false);

    QVBoxLayout *m_mainLayout;
    QLabel *m_titleLabel;
    QLabel *m_subtitleLabel;
    ResponsiveQLabel *m_imageLabel;
    QLabel *m_instructionLabel;
    QLabel *m_githubLabel;
};

#endif // WELCOMEWIDGET_H