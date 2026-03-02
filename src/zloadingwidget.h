#ifndef ZLOADINGWIDGET_H
#define ZLOADINGWIDGET_H

#include <QLabel>
#include <QPushButton>
#include <QStackedWidget>
#include <QWidget>
#include <QHBoxLayout>

class ZLoadingErrorWidget : public QWidget
{
    Q_OBJECT
public:
    ZLoadingErrorWidget(QWidget *parent = nullptr)
    {

        QHBoxLayout *layout = new QHBoxLayout(this);
        layout->addStretch();
        m_errorLabel = new QLabel("An error occurred.", this);
        m_errorLabel->setAlignment(Qt::AlignCenter);
        m_errorLabel->setStyleSheet("QLabel { color: red; }");
        layout->addWidget(m_errorLabel);
        m_retryButton = new QPushButton("Retry", this);
        m_retryButton->setMaximumWidth(m_retryButton->sizeHint().width());
        layout->addWidget(m_retryButton);
        layout->addStretch();
        connect(m_retryButton, &QPushButton::clicked, this,
                [this]() { emit retryClicked(); });
    }

    void setText(const QString &text) { m_errorLabel->setText(text); };

private:
    QLabel *m_errorLabel;
    QPushButton *m_retryButton;
signals:
    void retryClicked();
};

class ZLoadingWidget : public QStackedWidget
{
    Q_OBJECT
public:
    explicit ZLoadingWidget(bool start = true, QWidget *parent = nullptr);
    ~ZLoadingWidget();
    void stop(bool showContent = true);
    void showLoading();
    void setupContentWidget(QWidget *contentWidget);
    void setupContentWidget(QLayout *contentLayout);
    void setupErrorWidget(QWidget *errorWidget);
    void setupErrorWidget(QLayout *errorLayout);
    void setupAditionalWidget(QWidget *customWidget);
    void switchToWidget(QWidget *widget);
    void showError();
    void showError(const QString &errorMessage);

private:
    class QProcessIndicator *m_loadingIndicator = nullptr;
    QWidget *m_contentWidget = nullptr;
    QWidget *m_errorWidget = nullptr;
signals:
    void retryClicked();
};

#endif // ZLOADINGWIDGET_H
