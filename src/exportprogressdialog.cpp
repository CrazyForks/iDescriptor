/*
 * iDescriptor: A free and open-source idevice management tool.
 *
 * Copyright (C) 2025 Uncore <https://github.com/uncor3>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include "exportprogressdialog.h"
#include "exportmanager.h"
#include "iDescriptor.h"
#include <QApplication>
#include <QCloseEvent>
#include <QDateTime>
#include <QDebug>
#include <QDesktopServices>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QMessageBox>
#include <QPalette>
#include <QStyle>
#include <QUrl>

ExportProgressDialog::ExportProgressDialog(ExportManager *exportManager,
                                           QWidget *parent)
    : QDialog(parent), m_exportManager(exportManager), m_totalItems(0),
      m_completedItems(0), m_totalBytesTransferred(0),
      m_lastBytesTransferred(0), m_jobCompleted(false), m_jobCancelled(false)
{
    setupUI();

    // Connect to export manager signals
    connect(m_exportManager, &ExportManager::exportStarted, this,
            &ExportProgressDialog::onExportStarted);
    connect(m_exportManager, &ExportManager::exportProgress, this,
            &ExportProgressDialog::onExportProgress);
    connect(m_exportManager, &ExportManager::fileTransferProgress, this,
            &ExportProgressDialog::onFileTransferProgress);
    connect(m_exportManager, &ExportManager::itemExported, this,
            &ExportProgressDialog::onItemExported);
    connect(m_exportManager, &ExportManager::exportFinished, this,
            &ExportProgressDialog::onExportFinished);
    connect(m_exportManager, &ExportManager::exportCancelled, this,
            &ExportProgressDialog::onExportCancelled);

    // Setup transfer rate timer
    m_transferRateTimer = new QTimer(this);
    m_transferRateTimer->setInterval(1000); // Update every second
    connect(m_transferRateTimer, &QTimer::timeout, this,
            &ExportProgressDialog::updateTransferRate);

    // FIXME:Listen for palette changes
    // connect(qApp, &QApplication::paletteChanged, this,
    //         &ExportProgressDialog::updateColors);

    updateColors();
}

void ExportProgressDialog::setupUI()
{
    setWindowTitle("Exporting Files");
    setModal(true);
    setFixedSize(480, 280);
    setWindowFlags(Qt::Dialog | Qt::WindowTitleHint | Qt::CustomizeWindowHint);

    m_mainLayout = new QVBoxLayout(this);
    m_mainLayout->setSpacing(16);
    m_mainLayout->setContentsMargins(24, 24, 24, 24);

    // Title
    m_titleLabel = new QLabel("Exporting Files");
    m_titleLabel->setAlignment(Qt::AlignCenter);
    QFont titleFont = m_titleLabel->font();
    titleFont.setPointSize(titleFont.pointSize() + 4);
    titleFont.setWeight(QFont::Medium);
    m_titleLabel->setFont(titleFont);
    m_mainLayout->addWidget(m_titleLabel);

    // Status label
    m_statusLabel = new QLabel("Preparing export...");
    m_statusLabel->setAlignment(Qt::AlignCenter);
    m_statusLabel->setWordWrap(true);
    m_mainLayout->addWidget(m_statusLabel);

    // Current file label
    m_currentFileLabel = new QLabel();
    m_currentFileLabel->setAlignment(Qt::AlignCenter);
    m_currentFileLabel->setWordWrap(true);
    QFont fileFont = m_currentFileLabel->font();
    fileFont.setWeight(QFont::Medium);
    m_currentFileLabel->setFont(fileFont);
    m_mainLayout->addWidget(m_currentFileLabel);

    // Progress bar
    m_progressBar = new QProgressBar();
    m_progressBar->setRange(0, 100);
    m_progressBar->setValue(0);
    m_progressBar->setFixedHeight(8);
    m_progressBar->setTextVisible(false);
    m_mainLayout->addWidget(m_progressBar);

    // Stats label (items completed)
    m_statsLabel = new QLabel("0 of 0 items");
    m_statsLabel->setAlignment(Qt::AlignCenter);
    m_mainLayout->addWidget(m_statsLabel);

    // Transfer rate
    m_transferRateLabel = new QLabel();
    m_transferRateLabel->setAlignment(Qt::AlignCenter);
    m_mainLayout->addWidget(m_transferRateLabel);

    // Time remaining
    m_timeRemainingLabel = new QLabel();
    m_timeRemainingLabel->setAlignment(Qt::AlignCenter);
    m_mainLayout->addWidget(m_timeRemainingLabel);

    // Add stretch before buttons
    m_mainLayout->addStretch();

    // Buttons layout
    QHBoxLayout *buttonLayout = new QHBoxLayout();
    buttonLayout->addStretch();

    m_cancelButton = new QPushButton("Cancel");
    m_cancelButton->setMaximumWidth(m_cancelButton->sizeHint().width());
    connect(m_cancelButton, &QPushButton::clicked, this,
            &ExportProgressDialog::onCancelClicked);
    buttonLayout->addWidget(m_cancelButton);

    m_closeButton = new QPushButton("Close");
    m_closeButton->setMaximumWidth(m_closeButton->sizeHint().width());
    m_closeButton->setVisible(false);
    connect(m_closeButton, &QPushButton::clicked, this, &QDialog::accept);
    buttonLayout->addWidget(m_closeButton);

    m_openDirButton = new QPushButton("Show Files");
    m_openDirButton->setMaximumWidth(m_openDirButton->sizeHint().width());
    m_openDirButton->setVisible(false);
    connect(m_openDirButton, &QPushButton::clicked, this,
            &ExportProgressDialog::onOpenDirectoryClicked);
    buttonLayout->addWidget(m_openDirButton);

    buttonLayout->addStretch();
    m_mainLayout->addLayout(buttonLayout);
}

// TODO:
void ExportProgressDialog::updateColors()
{
    // QPalette palette = qApp->palette();

    // Apply Apple-style colors
    // QString dialogStyle =
    //     QString("QDialog {"
    //             "    background-color: %1;"
    //             "    border-radius: 12px;"
    //             "}"
    //             "QLabel {"
    //             "    color: %2;"
    //             "}"
    //             "QProgressBar {"
    //             "    border: none;"
    //             "    border-radius: 4px;"
    //             "    background-color: %3;"
    //             "}"
    //             "QProgressBar::chunk {"
    //             "    background-color: %4;"
    //             "    border-radius: 4px;"
    //             "}"
    //             "QPushButton {"
    //             "    background-color: %5;"
    //             "    color: %6;"
    //             "    border: 1px solid %7;"
    //             "    border-radius: 6px;"
    //             "    padding: 6px 12px;"
    //             "    font-weight: 500;"
    //             "}"
    //             "QPushButton:hover {"
    //             "    background-color: %8;"
    //             "}"
    //             "QPushButton:pressed {"
    //             "    background-color: %9;"
    //             "}")
    //         .arg(palette.color(QPalette::Base).name())
    //         .arg(palette.color(QPalette::WindowText).name())
    //         .arg(palette.color(QPalette::AlternateBase).name())
    //         .arg(palette.color(QPalette::Highlight).name())
    //         .arg(palette.color(QPalette::Button).name())
    //         .arg(palette.color(QPalette::ButtonText).name())
    //         .arg(palette.color(QPalette::Mid).name())
    //         .arg(palette.color(QPalette::Button).lighter(110).name())
    //         .arg(palette.color(QPalette::Button).darker(110).name());

    // setStyleSheet(dialogStyle);

    // // Special styling for title
    // m_titleLabel->setStyleSheet(
    //     QString("color: %1; font-weight: 600;")
    //         .arg(palette.color(QPalette::WindowText).name()));
}

void ExportProgressDialog::showForJob(const QUuid &jobId)
{
    m_currentJobId = jobId;
    m_jobCompleted = false;
    m_jobCancelled = false;
    m_totalBytesTransferred = 0;
    m_lastBytesTransferred = 0;
    m_completedItems = 0;

    // Reset UI
    m_progressBar->setValue(0);
    m_statusLabel->setText("Preparing export...");
    m_currentFileLabel->clear();
    m_statsLabel->setText("0 of 0 items");
    m_transferRateLabel->clear();
    m_timeRemainingLabel->clear();
    m_cancelButton->setVisible(true);
    m_closeButton->setVisible(false);
    m_openDirButton->setVisible(false);

    show();
    raise();
    activateWindow();
}

void ExportProgressDialog::onExportStarted(const QUuid &jobId, int totalItems,
                                           const QString &destinationPath)
{
    if (jobId != m_currentJobId)
        return;

    m_totalItems = totalItems;
    m_completedItems = 0;
    m_destinationPath = destinationPath;
    m_startTime = QDateTime::currentDateTime();
    m_lastUpdateTime = m_startTime;

    m_statusLabel->setText(QString("Exporting %1 items to %2")
                               .arg(totalItems)
                               .arg(QFileInfo(destinationPath).baseName()));
    m_statsLabel->setText(QString("0 of %1 items").arg(totalItems));

    m_transferRateTimer->start();
}

void ExportProgressDialog::onExportProgress(const QUuid &jobId, int currentItem,
                                            int totalItems,
                                            const QString &currentFileName)
{
    if (jobId != m_currentJobId)
        return;

    // Update current file
    m_currentFileLabel->setText(currentFileName);

    // Update stats
    m_statsLabel->setText(
        QString("%1 of %2 items").arg(currentItem).arg(totalItems));
}

void ExportProgressDialog::onFileTransferProgress(const QUuid &jobId,
                                                  const QString &fileName,
                                                  qint64 bytesTransferred,
                                                  qint64 totalFileSize)
{
    if (jobId != m_currentJobId)
        return;

    // Update progress bar based on current file transfer
    int progress =
        totalFileSize > 0 ? (bytesTransferred * 100) / totalFileSize : 0;
    m_progressBar->setValue(progress);

    // Update transfer info
    QString transferInfo = QString("%1 / %2")
                               .arg(formatFileSize(bytesTransferred))
                               .arg(formatFileSize(totalFileSize));
    m_transferRateLabel->setText(transferInfo);
}

void ExportProgressDialog::onItemExported(const QUuid &jobId,
                                          const ExportResult &result)
{
    if (jobId != m_currentJobId)
        return;

    if (result.success) {
        m_completedItems++;
        m_totalBytesTransferred += result.bytesTransferred;
    }
}

void ExportProgressDialog::onExportFinished(const QUuid &jobId,
                                            const ExportJobSummary &summary)
{
    if (jobId != m_currentJobId)
        return;

    m_jobCompleted = true;
    m_transferRateTimer->stop();

    m_destinationPath = summary.destinationPath;

    m_progressBar->setValue(100);
    m_currentFileLabel->clear();

    QString message;
    if (summary.failedItems == 0) {
        message = QString("Successfully exported %1 items")
                      .arg(summary.successfulItems);
        m_titleLabel->setText("Export Complete");
    } else {
        message = QString("Exported %1 items (%2 failed)")
                      .arg(summary.successfulItems)
                      .arg(summary.failedItems);
        m_titleLabel->setText("Export Completed with Errors");
    }

    m_statusLabel->setText(message);
    m_transferRateLabel->setText(
        QString("Total: %1")
            .arg(formatFileSize(summary.totalBytesTransferred)));
    m_timeRemainingLabel->clear();

    // Show close button, hide cancel
    m_cancelButton->setVisible(false);
    m_closeButton->setVisible(true);
    m_openDirButton->setVisible(true);
    m_closeButton->setDefault(true);
    m_closeButton->setFocus();
}

void ExportProgressDialog::onExportCancelled(const QUuid &jobId)
{
    if (jobId != m_currentJobId)
        return;

    m_jobCancelled = true;
    m_transferRateTimer->stop();

    m_titleLabel->setText("Export Cancelled");
    m_statusLabel->setText("Export was cancelled by user");
    m_currentFileLabel->clear();
    m_transferRateLabel->clear();
    m_timeRemainingLabel->clear();

    // Show close button, hide cancel
    m_cancelButton->setVisible(false);
    m_closeButton->setVisible(true);
    m_closeButton->setDefault(true);
    m_closeButton->setFocus();
}

void ExportProgressDialog::onCancelClicked()
{
    int reply = QMessageBox::question(
        this, "Cancel Export", "Are you sure you want to cancel the export?",
        QMessageBox::Yes | QMessageBox::No, QMessageBox::No);

    if (reply == QMessageBox::Yes) {
        m_exportManager->cancelExport(m_currentJobId);
        m_cancelButton->setEnabled(false);
        m_cancelButton->setText("Cancelling...");
    }
}

void ExportProgressDialog::onOpenDirectoryClicked()
{
    qDebug() << "Opening export directory:" << m_destinationPath;
    if (!m_destinationPath.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_destinationPath));
        QTimer::singleShot(100, this, &QDialog::accept);
    }
}

void ExportProgressDialog::updateTransferRate()
{
    if (m_jobCompleted || m_jobCancelled) {
        return;
    }

    QDateTime now = QDateTime::currentDateTime();
    qint64 elapsed = m_lastUpdateTime.msecsTo(now);

    if (elapsed > 0) {
        qint64 bytesDiff = m_totalBytesTransferred - m_lastBytesTransferred;
        qint64 bytesPerSecond = (bytesDiff * 1000) / elapsed;

        m_transferRateLabel->setText(formatTransferRate(bytesPerSecond));

        // Calculate time remaining
        if (bytesPerSecond > 0 && m_completedItems > 0) {
            qint64 avgBytesPerItem = m_totalBytesTransferred / m_completedItems;
            qint64 remainingBytes =
                (m_totalItems - m_completedItems) * avgBytesPerItem;
            int secondsRemaining =
                static_cast<int>(remainingBytes / bytesPerSecond);

            if (secondsRemaining > 0 &&
                secondsRemaining < 3600) { // Only show if less than 1 hour
                m_timeRemainingLabel->setText(
                    formatTimeRemaining(secondsRemaining));
            }
        }
    }

    m_lastBytesTransferred = m_totalBytesTransferred;
    m_lastUpdateTime = now;
}

void ExportProgressDialog::changeEvent(QEvent *event)
{
    if (event->type() == QEvent::PaletteChange) {
        updateColors();
    }
    QDialog::changeEvent(event);
}

void ExportProgressDialog::closeEvent(QCloseEvent *event)
{
    if (!m_jobCompleted && !m_jobCancelled) {
        // Ask user if they want to cancel the ongoing export
        int reply = QMessageBox::question(
            this, "Export in Progress",
            "An export is currently in progress. Do you want to cancel it?",
            QMessageBox::Yes | QMessageBox::No, QMessageBox::No);

        if (reply == QMessageBox::Yes) {
            m_exportManager->cancelExport(m_currentJobId);
            event->accept();
        } else {
            event->ignore();
        }
    } else {
        event->accept();
    }
}

QString ExportProgressDialog::formatFileSize(qint64 bytes) const
{
    const qint64 KB = 1024;
    const qint64 MB = KB * 1024;
    const qint64 GB = MB * 1024;

    if (bytes >= GB) {
        return QString("%1 GB").arg(
            QString::number(bytes / double(GB), 'f', 2));
    } else if (bytes >= MB) {
        return QString("%1 MB").arg(
            QString::number(bytes / double(MB), 'f', 1));
    } else if (bytes >= KB) {
        return QString("%1 KB").arg(
            QString::number(bytes / double(KB), 'f', 0));
    } else {
        return QString("%1 bytes").arg(bytes);
    }
}

QString ExportProgressDialog::formatTransferRate(qint64 bytesPerSecond) const
{
    return QString("%1/s").arg(formatFileSize(bytesPerSecond));
}

QString ExportProgressDialog::formatTimeRemaining(int secondsRemaining) const
{
    if (secondsRemaining < 60) {
        return QString("%1 seconds remaining").arg(secondsRemaining);
    } else {
        int minutes = secondsRemaining / 60;
        int seconds = secondsRemaining % 60;
        return QString("%1:%2 remaining")
            .arg(minutes)
            .arg(seconds, 2, 10, QLatin1Char('0'));
    }
}