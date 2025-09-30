#ifndef IFUSEWIDGET_H
#define IFUSEWIDGET_H

#include "appcontext.h"
#include "clickablelabel.h"
#include "iDescriptor.h"
#include <QCheckBox>
#include <QComboBox>
#include <QDesktopServices>
#include <QDir>
#include <QFileDialog>
#include <QHBoxLayout>
#include <QLabel>
#include <QMessageBox>
#include <QProcess>
#include <QPushButton>
#include <QUrl>
#include <QVBoxLayout>
#include <QWidget>

class iFuseWidget : public QWidget
{
    Q_OBJECT

public:
    explicit iFuseWidget(iDescriptorDevice *device, QWidget *parent = nullptr);
    ~iFuseWidget();

private slots:
    void onFolderPickerClicked();
    void onMountPathClicked();
    void onMountClicked();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError error);
    void refreshDevices();

private:
    void setupUI();
    void updateDeviceComboBox();
    bool validateInputs();
    QString getSelectedDeviceUdid();
    void setStatusMessage(const QString &message, bool isError = false);
    void onDeviceChanged(const QString &deviceName);
    // UI Components
    QVBoxLayout *m_mainLayout;
    QLabel *m_descriptionLabel;
    QLabel *m_statusLabel;
    QComboBox *m_deviceComboBox;
    ClickableLabel *m_mountPathLabel;
    QPushButton *m_folderPickerButton;
    QLabel *m_folderNameLabel;
    QPushButton *m_mountButton;
    iDescriptorDevice *m_device;

    // Data
    QString m_selectedPath;
    QProcess *m_ifuseProcess;
    QString m_currentMountPath;
};

#endif // IFUSEWIDGET_H