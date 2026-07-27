import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "." as App
import "./base"

Item {
    id: root
    Layout.fillWidth: true
    Layout.preferredHeight: 28

    Layout.leftMargin: 10
    Layout.rightMargin: 10
    Layout.topMargin: 5
    Layout.bottomMargin: 5

    WhatsNew {
        id: whatsNewDialog
    }
    
    RowLayout {
        anchors.fill: parent
        spacing: Qt.platform.os === "windows" ? 2 : 5
        Label {
            text : App.DeviceContext.getDeviceCount() ? qsTr("iDescriptor: %1 device(s) connected").arg(App.DeviceContext.getDeviceCount()) : qsTr("iDescriptor: no devices")
        }
        IconToolButton {
            id: myButton
            icon.source: "qrc:/resources/icons/uim_process.svg"
            onClicked: {
                var globalPos = myButton.mapToGlobal(0, 0)
               
                StatusWindow.toggle(Window.window, globalPos, myButton.width, myButton.height)
            }
        }
        IconToolButton {
            id: welcomeButton
            visible: App.DeviceContext.currentTab === 0
            icon.source: "qrc:/resources/icons/lets-icons_horizontal-down-left-main-light.svg"
            onClicked: {
                App.DeviceContext.showWelcomePage = !App.DeviceContext.showWelcomePage
            }
        }

        Item { Layout.fillWidth: true }

        Loader {
            active: Qt.platform.os === "linux"
            visible: active
            sourceComponent: Component {
                RowLayout {
                    spacing: 2

                    Component.onCompleted: IFuseManager.refresh()

                    Connections {
                        target: iFuse

                        function onStateChanged() {
                            IFuseManager.refresh()
                        }
                    }

                    Connections {
                        target: IFuseManager

                        function onUnmountFinished(mountPath, success, error) {
                            if (success)
                                return

                            App.Helpers.messageBox(
                                root,
                                qsTr("Unmount Failed"),
                                qsTr("Failed to unmount iFuse at %1. Please try again. %2")
                                    .arg(mountPath)
                                    .arg(error),
                                MessageDialog.Ok
                            )
                        }
                    }

                    Repeater {
                        model: IFuseManager.mountPoints

                        delegate: IconToolButton {
                            required property string modelData
                            enabled: IFuseManager.busyPath.length === 0
                            icon.source: "qrc:/resources/icons/clarity_hard-disk-solid-alerted.svg"
                            ToolTip.visible: hovered
                            ToolTip.text: IFuseManager.busyPath === modelData
                                          ? qsTr("Unmounting iFuse at %1…").arg(modelData)
                                          : qsTr("Unmount iFuse at %1").arg(modelData)
                            onClicked: IFuseManager.unmount(modelData)
                        }
                    }
                }
            }
        }

        Label {
            text: qsTr("v%1").arg(settingsManager.current_version())
            color: App.Theme.textMuted
            font.pixelSize: 11
        }
        IconToolButton {
            icon.source: "qrc:/resources/icons/mdi_github.svg"
            onClicked: Qt.openUrlExternally(App.Constants.repoUrl)
        }

        IconToolButton {
            id: settingsButton
            icon.source: "qrc:/resources/icons/mingcute_settings-7-line.svg"
            onClicked: App.Settings.open()
        }

    }

    Component.onCompleted: {
        StatusWindow.registerStatusBarOpener(Window.window, myButton)
        Qt.callLater(whatsNewDialog.showIfNeeded)
    }
    Component.onDestruction: StatusWindow.unregisterStatusBarOpener(myButton)
}
