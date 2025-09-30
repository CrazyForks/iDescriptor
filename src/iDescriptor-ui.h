#pragma once
#include <QGraphicsView>
#include <QMainWindow>

#define COLOR_GREEN QColor(0, 180, 0)    // Green
#define COLOR_ORANGE QColor(255, 140, 0) // Orange
#define COLOR_RED QColor(255, 0, 0)      // Red

// A custom QGraphicsView that keeps the content fitted with aspect ratio on
// resize
class ResponsiveGraphicsView : public QGraphicsView
{
public:
    ResponsiveGraphicsView(QGraphicsScene *scene, QWidget *parent = nullptr)
        : QGraphicsView(scene, parent)
    {
    }

protected:
    void resizeEvent(QResizeEvent *event) override
    {
        if (scene() && !scene()->items().isEmpty()) {
            fitInView(scene()->itemsBoundingRect(), Qt::KeepAspectRatio);
        }
        QGraphicsView::resizeEvent(event);
    }
};

#ifdef Q_OS_MAC
void setupMacOSWindow(QMainWindow *window);
#endif
