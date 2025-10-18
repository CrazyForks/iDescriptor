#ifndef WIRELESSPHOTOIMPORTWIDGET_H
#define WIRELESSPHOTOIMPORTWIDGET_H

#include "qprocessindicator.h"
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QMediaPlayer>
#include <QPushButton>
#include <QScrollArea>
#include <QStringList>
#include <QVBoxLayout>
#include <QVideoWidget>
#include <QWidget>

class WirelessPhotoImportWidget : public QWidget
{
    Q_OBJECT

public:
    explicit WirelessPhotoImportWidget(QWidget *parent = nullptr);
    ~WirelessPhotoImportWidget();

    QStringList getSelectedFiles() const;

private slots:
    void onBrowseFiles();
    void onImportPhotos();
    void onRemoveFile(int index);
    void setupTutorialVideo();

private:
    // Left panel - file selection
    QWidget *m_leftPanel;
    QScrollArea *m_scrollArea;
    QWidget *m_scrollContent;
    QVBoxLayout *m_fileListLayout;
    QPushButton *m_browseButton;
    QPushButton *m_importButton;
    QLabel *m_statusLabel;

    // Right panel - tutorial video
    QWidget *m_rightPanel;
    QMediaPlayer *m_tutorialPlayer;
    QVideoWidget *m_tutorialVideoWidget;
    QProcessIndicator *m_loadingIndicator;
    QLabel *m_loadingLabel;
    QVBoxLayout *m_tutorialLayout;

    QStringList m_selectedFiles;

    void setupUI();
    void updateFileList();
    void updateStatusLabel();
    bool isGalleryCompatible(const QString &filePath) const;
    QStringList getGalleryCompatibleExtensions() const;
};

#endif // WIRELESSPHOTOIMPORTWIDGET_H
