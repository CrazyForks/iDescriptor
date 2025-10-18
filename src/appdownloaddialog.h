#ifndef APPDOWNLOADDIALOG_H
#define APPDOWNLOADDIALOG_H

#include "appdownloadbasedialog.h"
#include "iDescriptor-ui.h"
#include <QDialog>
#include <QLabel>
#include <QPushButton>

class AppDownloadDialog : public AppDownloadBaseDialog
{
    Q_OBJECT
public:
    explicit AppDownloadDialog(const QString &appName, const QString &bundleId,
                               const QString &description,
                               QWidget *parent = nullptr);

private slots:
    void onDownloadClicked();

private:
    QString m_outputDir;
    QPushButton *m_dirButton;
    ZLabel *m_dirLabel;
    QString m_bundleId;
};

#endif // APPDOWNLOADDIALOG_H
