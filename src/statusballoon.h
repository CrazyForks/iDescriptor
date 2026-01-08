#ifndef STATUSBALLOON_H
#define STATUSBALLOON_H

#include "iDescriptor-ui.h"
#include "iDescriptor.h"
#include "qballoontip.h"
#include <QBasicTimer>
#include <QDateTime>
#include <QIcon>
#include <QLabel>
#include <QMutex>
#include <QProgressBar>
#include <QPushButton>
#include <QSystemTrayIcon>
#include <QUuid>
#include <QVBoxLayout>
#include <QWidget>
#include <atomic>

enum class ProcessType { Export, Upload };

enum class ProcessStatus { Queued, Running, Completed, Failed, Cancelled };

struct ProcessItem {
    QUuid processId;
    ProcessType type;
    ProcessStatus status;
    QString title;
    QString currentFile;
    int totalItems;
    int completedItems;
    int failedItems;
    qint64 totalBytes;
    qint64 transferredBytes;
    QDateTime startTime;
    QDateTime endTime;
    QString destinationPath; // For export
    QWidget *processWidget;
    QLabel *titleLabel;
    QLabel *statusLabel;
    QLabel *statsLabel;
    QProgressBar *progressBar;
    QPushButton *actionButton;
    QPushButton *cancelButton;
    std::atomic<bool> cancelRequested{false};
};

class Process : public QWidget
{
    Q_OBJECT
public:
    explicit Process(QWidget *parent = nullptr);
};

class StatusBalloon : public QBalloonTip
{
    Q_OBJECT
public:
    explicit StatusBalloon(QWidget *parent = nullptr);
    static StatusBalloon *sharedInstance();

    // Process management
    QUuid startExportProcess(const QString &title, int totalItems,
                             const QString &destinationPath);
    QUuid startUploadProcess(const QString &title, int totalItems);

    void onFileTransferProgress(const QUuid &processId, int currentItem,
                                const QString &currentFile,
                                qint64 bytesTransferred, qint64 totalBytes);
    void markProcessCompleted(const QUuid &processId);
    void markProcessFailed(const QUuid &processId, const QString &error);
    void markProcessCancelled(const QUuid &processId);
    void incrementFailedItems(const QUuid &processId);

    bool isProcessRunning(const QUuid &processId) const;
    bool hasActiveProcesses() const;
    bool isCancelRequested(const QUuid &processId) const;
    ZIconWidget *getButton();
private slots:
    void onCancelClicked();
    void onOpenFolderClicked();

private:
    void updateUI();
    void showBalloon();
    void createProcessWidget(ProcessItem *item);
    QString formatFileSize(qint64 bytes) const;
    QString formatTransferRate(qint64 bytesPerSecond) const;
    void removeProcessWidget(const QUuid &processId);
    void connectExportThreadSignals();
    void onExportFinished(const QUuid &processId,
                          const ExportJobSummary &summary);
    void onItemExported(const QUuid &processId, const ExportResult &result);

    QVBoxLayout *m_mainLayout;
    QLabel *m_headerLabel;
    QWidget *m_processesContainer;
    QVBoxLayout *m_processesLayout;

    QMap<QUuid, ProcessItem *> m_processes;
    QUuid m_currentProcessId;
    mutable QMutex m_processesMutex;

    QMap<QUuid, qint64> m_lastBytesTransferred;
    QMap<QUuid, QDateTime> m_lastUpdateTime;
    ZIconWidget *m_button =
        new ZIconWidget(QIcon(":/resources/icons/UimProcess.png"), "Processes");
};
#endif // STATUSBALLOON_H
