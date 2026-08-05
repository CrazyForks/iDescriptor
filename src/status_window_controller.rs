// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use cpp::cpp;
use log::debug;
use qmetaobject::{QJSValue, prelude::*};

// Why do we need this?
/*
  We need an event filter to detect clicks outside the status window
  the most reliable way to do this seems to be installing an event filter on the application
  not sure if there is a better way to do this but this works and is simple enough
*/

cpp! {{
    #include <QCoreApplication>
    #include <QEvent>
    #include <QKeyEvent>
    #include <QMetaObject>
    #include <QMouseEvent>
    #include <QObject>
    #include <QPointer>
    #include <QRect>
    #include <QWindow>
    #include <QJSValue>

    class StatusWindowEventFilter : public QObject {
    public:
        StatusWindowEventFilter(QObject *receiver, QObject *statusWindow, const QRect &openerRect)
            : QObject(QCoreApplication::instance()),
              receiver(receiver),
              statusWindow(statusWindow),
              openerRect(openerRect)
        {
        }

        void update(QObject *receiver, QObject *statusWindow, const QRect &openerRect)
        {
            this->receiver = receiver;
            this->statusWindow = statusWindow;
            this->openerRect = openerRect;
            this->closePending = false;
        }

    protected:
        bool eventFilter(QObject *obj, QEvent *event) override
        {
            if (!receiver) {
                return false;
            }

            switch (event->type()) {
            case QEvent::MouseButtonPress: {
                auto *mouseEvent = static_cast<QMouseEvent *>(event);
                QPoint globalPos;
            #if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
                globalPos = mouseEvent->globalPosition().toPoint();
            #else
                globalPos = mouseEvent->globalPos();
            #endif

                if (openerRect.isValid() && openerRect.contains(globalPos)) {
                    return false;
                }

                if (statusWindow) {
                    if (auto *window = qobject_cast<QWindow *>(statusWindow.data())) {
                        if (window->geometry().contains(globalPos)) {
                            return false;
                        }
                    }
                }

                requestClose(QStringLiteral("outsideMousePress"));
                return true;
            }
            case QEvent::WindowDeactivate:
                if (obj == statusWindow.data()) {
                    requestClose(QStringLiteral("windowDeactivate"));
                }
                return false;
            case QEvent::ApplicationDeactivate:
                requestClose(QStringLiteral("applicationDeactivate"));
                return false;
            case QEvent::KeyPress: {
                auto *keyEvent = static_cast<QKeyEvent *>(event);
                if (keyEvent->key() == Qt::Key_Escape) {
                    requestClose(QStringLiteral("escape"));
                    return true;
                }
                return false;
            }
            default:
                return false;
            }
        }

    private:
        void requestClose(const QString &reason)
        {
            if (closePending || !receiver) {
                return;
            }

            closePending = true;
            QMetaObject::invokeMethod(
                receiver.data(),
                "emit_close_requested",
                Qt::QueuedConnection,
                Q_ARG(QString, reason)
            );
        }

        QPointer<QObject> receiver;
        QPointer<QObject> statusWindow;
        QRect openerRect;
        bool closePending = false;
    };

    static StatusWindowEventFilter *statusWindowEventFilter = nullptr;

    static void installStatusWindowEventFilter(
        QObject *receiver,
        QObject *statusWindow,
        int openerX,
        int openerY,
        int openerWidth,
        int openerHeight
    ) {
        QCoreApplication *app = QCoreApplication::instance();
        if (!app || !receiver || !statusWindow) {
            return;
        }

        QRect openerRect;
        if (openerWidth > 0 && openerHeight > 0) {
            openerRect = QRect(openerX, openerY, openerWidth, openerHeight);
        }

        if (!statusWindowEventFilter) {
            statusWindowEventFilter = new StatusWindowEventFilter(receiver, statusWindow, openerRect);
            app->installEventFilter(statusWindowEventFilter);
        } else {
            statusWindowEventFilter->update(receiver, statusWindow, openerRect);
        }
    }

    static void uninstallStatusWindowEventFilter()
    {
        QCoreApplication *app = QCoreApplication::instance();
        if (app && statusWindowEventFilter) {
            app->removeEventFilter(statusWindowEventFilter);
        }

        delete statusWindowEventFilter;
        statusWindowEventFilter = nullptr;
    }
}}

#[allow(non_snake_case)]
#[derive(QObject, Default)]
pub struct StatusWindowController {
    base: qt_base_class!(trait QObject),
    install: qt_method!(
        fn(
            &mut self,
            status_window: QJSValue,
            opener_x: f64,
            opener_y: f64,
            opener_width: f64,
            opener_height: f64,
        )
    ),
    uninstall: qt_method!(fn(&mut self)),
    emit_close_requested: qt_method!(fn(&mut self, reason: QString)),
    closeRequested: qt_signal!(reason: QString),
}

impl StatusWindowController {
    fn install(
        &mut self,
        status_window: QJSValue,
        opener_x: f64,
        opener_y: f64,
        opener_width: f64,
        opener_height: f64,
    ) {
        let receiver = QPointer::from(&*self).cpp_ptr();

        let installed = unsafe {
            cpp!([
                receiver as "QObject *",
                status_window as "QJSValue",
                opener_x as "double",
                opener_y as "double",
                opener_width as "double",
                opener_height as "double"
            ] -> bool as "bool" {
                QObject *statusWindow = status_window.toQObject();
                if (!receiver || !statusWindow) {
                    return false;
                }

                installStatusWindowEventFilter(
                    receiver,
                    statusWindow,
                    static_cast<int>(opener_x),
                    static_cast<int>(opener_y),
                    static_cast<int>(opener_width),
                    static_cast<int>(opener_height)
                );
                return true;
            })
        };

        if !installed {
            debug!("StatusWindowController failed to install event filter");
        }
    }

    fn uninstall(&mut self) {
        unsafe {
            cpp!([] {
                uninstallStatusWindowEventFilter();
            });
        }
    }

    fn emit_close_requested(&mut self, reason: QString) {
        self.closeRequested(reason);
    }
}

impl Drop for StatusWindowController {
    fn drop(&mut self) {
        self.uninstall();
    }
}
