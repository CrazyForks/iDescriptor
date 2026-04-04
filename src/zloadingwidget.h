#ifndef ZLOADINGWIDGET_H
#define ZLOADINGWIDGET_H

#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QStackedWidget>
#include <QWidget>

class ZLoadingErrorWidget : public QWidget
{
    Q_OBJECT
public:
    ZLoadingErrorWidget(bool retryEnabled, QWidget *parent = nullptr)
    {

        QVBoxLayout *layout = new QVBoxLayout(this);
        layout->addStretch();
        m_errorLabel = new QLabel("An error occurred.", this);
        m_errorLabel->setAlignment(Qt::AlignCenter);
        m_errorLabel->setWordWrap(true);
        m_errorLabel->setStyleSheet("QLabel { color: red; }");
        layout->addWidget(m_errorLabel);

        if (retryEnabled) {
            layout->addSpacing(10);
            m_retryButton = new QPushButton("Retry", this);
            m_retryButton->setMaximumWidth(m_retryButton->sizeHint().width());
            layout->addWidget(m_retryButton, 0, Qt::AlignCenter);
            connect(m_retryButton, &QPushButton::clicked, this,
                    [this]() { emit retryClicked(); });
        }
        layout->addStretch();
    }

    void setText(const QString &text) { m_errorLabel->setText(text); };

private:
    QLabel *m_errorLabel = nullptr;
    QPushButton *m_retryButton = nullptr;
signals:
    void retryClicked();
};

class ZLoadingWidget : public QStackedWidget
{
    Q_OBJECT
public:
    explicit ZLoadingWidget(bool retryEnabled = false,
                            QWidget *parent = nullptr);
    ~ZLoadingWidget();
    void stop(bool showContent = true);
    void showLoading();
    void setupContentWidget(QWidget *contentWidget);
    void setupContentWidget(QLayout *contentLayout);
    void setupErrorWidget(QWidget *errorWidget);
    void setupErrorWidget(QLayout *errorLayout);
    int setupAditionalWidget(QWidget *customWidget);
    void switchToWidget(QWidget *widget);
    void showError();
    void showError(const QString &errorMessage);

private:
    class QProcessIndicator *m_loadingIndicator = nullptr;
    QWidget *m_contentWidget = nullptr;
    QWidget *m_errorWidget = nullptr;
    bool m_retryEnabled = false;
signals:
    void retryClicked();
};

#endif // ZLOADINGWIDGET_H
