#include "ifusewidget.h"
#include "clickablelabel.h"
#include "iDescriptor.h"
#include "ifusediskunmountbutton.h"
#include "ifusemanager.h"
#include "mainwindow.h"
#include <QDebug>
#include <QStandardPaths>
#include <QStatusBar>
#include <QTimer>

iFuseWidget::iFuseWidget(iDescriptorDevice *device, QWidget *parent)
    : QWidget(parent), m_mainLayout(nullptr), m_ifuseProcess(nullptr),
      m_device(device)
{
    setupUI();
    updateDeviceComboBox();

    // Connect to AppContext signals for device changes
    connect(AppContext::sharedInstance(), &AppContext::deviceAdded, this,
            &iFuseWidget::refreshDevices);
    connect(AppContext::sharedInstance(), &AppContext::deviceRemoved, this,
            &iFuseWidget::refreshDevices);
}

iFuseWidget::~iFuseWidget()
{
    if (m_ifuseProcess && m_ifuseProcess->state() == QProcess::Running) {
        m_ifuseProcess->kill();
        m_ifuseProcess->waitForFinished(3000);
    }
}

void iFuseWidget::setupUI()
{
    m_mainLayout = new QVBoxLayout(this);
    m_mainLayout->setSpacing(15);
    m_mainLayout->setContentsMargins(20, 20, 20, 20);

    // Description label
    m_descriptionLabel = new QLabel("This tool allows you to mount your "
                                    "iPhone's disk as a drive on your PC");
    m_descriptionLabel->setWordWrap(true);
    m_descriptionLabel->setStyleSheet(
        "font-size: 14px; color: #666; margin-bottom: 10px;");
    m_mainLayout->addWidget(m_descriptionLabel);

    // Status label
    m_statusLabel = new QLabel();
    m_statusLabel->setWordWrap(true);
    m_statusLabel->hide();
    m_statusLabel->setStyleSheet(
        "padding: 8px; border-radius: 4px; margin: 5px 0;");
    m_mainLayout->addWidget(m_statusLabel);

    // Device selection
    QWidget *deviceWidget = new QWidget();
    QHBoxLayout *deviceLayout = new QHBoxLayout(deviceWidget);
    deviceLayout->setContentsMargins(0, 0, 0, 0);

    QLabel *deviceLabel = new QLabel("Select Device:");
    deviceLabel->setMinimumWidth(100);
    m_deviceComboBox = new QComboBox();
    m_deviceComboBox->setMinimumHeight(35);

    deviceLayout->addWidget(deviceLabel);
    deviceLayout->addWidget(m_deviceComboBox, 1);
    m_mainLayout->addWidget(deviceWidget);

    // Mount path selection
    QWidget *pathWidget = new QWidget();
    QHBoxLayout *pathLayout = new QHBoxLayout(pathWidget);
    pathLayout->setContentsMargins(0, 0, 0, 0);

    m_mountPathLabel = new ClickableLabel();
    m_mountPathLabel->setText("Mount directory will be shown here");
    m_mountPathLabel->setStyleSheet("QLabel { "
                                    "border: 1px solid #ccc; "
                                    "padding: 8px; "
                                    "border-radius: 4px; "
                                    "background-color: #f9f9f9; "
                                    "}"
                                    "QLabel:hover { "
                                    "background-color: #f0f0f0; "
                                    "cursor: pointer; "
                                    "}");
    m_mountPathLabel->setMinimumHeight(35);

    m_folderPickerButton = new QPushButton("Browse...");
    m_folderPickerButton->setMinimumHeight(35);

    pathLayout->addWidget(m_mountPathLabel, 1);
    pathLayout->addWidget(m_folderPickerButton);
    m_mainLayout->addWidget(pathWidget);

    // Delete on unmount checkbox

    // Mount button
    m_mountButton = new QPushButton("Mount Device");
    m_mountButton->setMinimumHeight(40);
    m_mountButton->setStyleSheet("QPushButton { "
                                 "background-color: #007aff; "
                                 "color: white; "
                                 "border: none; "
                                 "border-radius: 6px; "
                                 "font-weight: bold; "
                                 "}"
                                 "QPushButton:hover { "
                                 "background-color: #0056cc; "
                                 "}"
                                 "QPushButton:disabled { "
                                 "background-color: #cccccc; "
                                 "}");
    m_mainLayout->addWidget(m_mountButton);

    // Add stretch to push everything to the top
    m_mainLayout->addStretch();

    // Connect signals
    connect(m_folderPickerButton, &QPushButton::clicked, this,
            &iFuseWidget::onFolderPickerClicked);
    connect(m_mountPathLabel, &ClickableLabel::clicked, this,
            &iFuseWidget::onMountPathClicked);
    connect(m_mountButton, &QPushButton::clicked, this,
            &iFuseWidget::onMountClicked);

    connect(m_deviceComboBox, &QComboBox::currentTextChanged, this,
            &iFuseWidget::onDeviceChanged);

    // Set default mount path based on device
    if (m_device) {
        QString homeDir =
            QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
        QString productType =
            QString::fromStdString(m_device->deviceInfo.productType);
        QString defaultMountPath = QDir(homeDir).absoluteFilePath(productType);
        m_mountPathLabel->setText(defaultMountPath);
    } else {
        QString homeDir =
            QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
        QString defaultMountPath = QDir(homeDir).absoluteFilePath("iPhone");
        m_mountPathLabel->setText(defaultMountPath);
    }
}

void iFuseWidget::updateDeviceComboBox()
{
    m_deviceComboBox->clear();

    QList<iDescriptorDevice *> devices =
        AppContext::sharedInstance()->getAllDevices();

    if (devices.isEmpty()) {
        close();
        return;
    }

    m_deviceComboBox->setEnabled(true);
    m_mountButton->setEnabled(true);

    for (iDescriptorDevice *device : devices) {
        QString displayText =
            QString::fromStdString(device->deviceInfo.productType) + " / " +
            QString::fromStdString(device->udid);
        m_deviceComboBox->addItem(displayText,
                                  QString::fromStdString(device->udid));
    }

    // Try to find and select the device passed to the widget
    int deviceIndex = -1;
    if (m_device) {
        deviceIndex =
            m_deviceComboBox->findData(QString::fromStdString(m_device->udid));
    }

    if (deviceIndex != -1) {
        // Found the pre-selected device, so select it.
        m_deviceComboBox->setCurrentIndex(deviceIndex);
    } else if (!devices.isEmpty()) {
        // Pre-selected device not found or not provided, so select the first
        // one.
        m_device = devices.first();
        m_deviceComboBox->setCurrentIndex(0);
    }
}

void iFuseWidget::onFolderPickerClicked()
{
    QString currentPath = m_mountPathLabel->text();
    QString dir = QFileDialog::getExistingDirectory(
        this, "Select Mount Directory", currentPath);
    if (!dir.isEmpty()) {
        m_mountPathLabel->setText(dir);
    }
}

void iFuseWidget::onMountPathClicked()
{
    QString currentPath = m_mountPathLabel->text();
    if (!currentPath.isEmpty() && QDir(currentPath).exists()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(currentPath));
    }
}

void iFuseWidget::onMountClicked()
{
    if (!validateInputs()) {
        return;
    }

    // Check if ifuse binary exists
    m_ifuseProcess = new QProcess(this);
    connect(m_ifuseProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            &iFuseWidget::onProcessFinished);
    connect(m_ifuseProcess, &QProcess::errorOccurred, this,
            &iFuseWidget::onProcessError);

    // First check if ifuse exists
    QProcess checkProcess;
    checkProcess.start("which", QStringList() << "ifuse");
    checkProcess.waitForFinished(3000);

    // todo: ship with ifuse binary
    if (checkProcess.exitCode() != 0) {
        setStatusMessage(
            "Error: ifuse binary not found. Please install ifuse first.", true);
        return;
    }

    // Create the mount directory
    QString homeDir =
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    QString productType =
        m_device ? QString::fromStdString(m_device->deviceInfo.productType)
                 : "iPhone";
    QString fullMountPath = QDir(homeDir).absoluteFilePath(productType);

    QDir dir;
    if (!QDir(fullMountPath).exists()) {
        if (!dir.mkpath(fullMountPath)) {
            setStatusMessage("Error: Failed to create mount directory: " +
                                 fullMountPath,
                             true);
            return;
        }
    }

    m_currentMountPath = fullMountPath;

    // Get selected device UDID
    QString deviceUdid = getSelectedDeviceUdid();

    setStatusMessage("Mounting device...", false);
    m_mountButton->setText("Mounting...");
    m_mountButton->setEnabled(false);

    // Run ifuse command
    QStringList arguments;
    arguments << "-u" << deviceUdid << fullMountPath;

    m_ifuseProcess->start("ifuse", arguments);
}

void iFuseWidget::onProcessFinished(int exitCode,
                                    QProcess::ExitStatus exitStatus)
{
    m_mountButton->setText("Mount Device");
    m_mountButton->setEnabled(true);

    if (exitStatus == QProcess::CrashExit) {
        setStatusMessage("Error: ifuse process crashed", true);
        return;
    }

    if (exitCode == 0) {
        setStatusMessage(
            "Device mounted successfully at: " + m_currentMountPath, false);

        auto *b = new iFuseDiskUnmountButton(m_currentMountPath);
        MainWindow::sharedInstance()->statusBar()->addPermanentWidget(b);

        connect(b, &iFuseDiskUnmountButton::clicked, this, [this, b]() {
            qDebug() << "Unmounting" << m_currentMountPath;
            bool ok = iFuseManager::linuxUnmount(m_currentMountPath);
            if (!ok) {
                QMessageBox::warning(nullptr, "Unmount Failed",
                                     "Failed to unmount iFuse at " +
                                         m_currentMountPath +
                                         ". Please try again.");
                return;
            }
            MainWindow::sharedInstance()->statusBar()->removeWidget(b);
            b->deleteLater();
        });
        // Open the mounted directory
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_currentMountPath));
    } else {
        QString errorOutput = m_ifuseProcess->readAllStandardError();
        setStatusMessage("Mount failed: " + errorOutput, true);
    }

    m_ifuseProcess->deleteLater();
    m_ifuseProcess = nullptr;
}

void iFuseWidget::onProcessError(QProcess::ProcessError error)
{
    m_mountButton->setText("Mount Device");
    m_mountButton->setEnabled(true);

    QString errorMessage;
    switch (error) {
    case QProcess::FailedToStart:
        errorMessage = "Failed to start ifuse. Make sure it's installed.";
        break;
    case QProcess::Crashed:
        errorMessage = "ifuse process crashed.";
        break;
    case QProcess::Timedout:
        errorMessage = "ifuse process timed out.";
        break;
    default:
        errorMessage = "Unknown error occurred.";
        break;
    }

    setStatusMessage("Error: " + errorMessage, true);

    if (m_ifuseProcess) {
        m_ifuseProcess->deleteLater();
        m_ifuseProcess = nullptr;
    }
}

void iFuseWidget::refreshDevices() { updateDeviceComboBox(); }

bool iFuseWidget::validateInputs()
{
    if (m_deviceComboBox->currentData().toString().isEmpty()) {
        setStatusMessage("Error: No device selected", true);
        return false;
    }

    return true;
}

QString iFuseWidget::getSelectedDeviceUdid()
{
    return m_deviceComboBox->currentData().toString();
}

void iFuseWidget::setStatusMessage(const QString &message, bool isError)
{
    m_statusLabel->setText(message);
    m_statusLabel->show();

    if (isError) {
        m_statusLabel->setStyleSheet(
            "background-color: #ffe6e6; color: #d00; border: 1px solid "
            "#ffcccc; padding: 8px; border-radius: 4px; margin: 5px 0;");
    } else {
        m_statusLabel->setStyleSheet(
            "background-color: #e6ffe6; color: #060; border: 1px solid "
            "#ccffcc; padding: 8px; border-radius: 4px; margin: 5px 0;");
    }

    // Auto-hide status after 5 seconds for non-error messages
    if (!isError) {
        QTimer::singleShot(5000, [this]() { m_statusLabel->hide(); });
    }
}

void iFuseWidget::onDeviceChanged(const QString &text)
{
    QString selectedUdid = m_deviceComboBox->currentData().toString();
    QList<iDescriptorDevice *> devices =
        AppContext::sharedInstance()->getAllDevices();

    for (iDescriptorDevice *device : devices) {
        if (QString::fromStdString(device->udid) == selectedUdid) {
            m_device = device;

            // Update mount path to reflect new device
            QString homeDir =
                QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
            QString productType =
                QString::fromStdString(device->deviceInfo.productType);
            QString newMountPath = QDir(homeDir).absoluteFilePath(productType);
            m_mountPathLabel->setText(newMountPath);

            break;
        }
    }
}