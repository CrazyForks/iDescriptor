import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import iDescriptor
import "../base"
import "../"

ToolWindow {
    id: root
    width: 420
    height: 760
    minimumWidth: 340
    minimumHeight: 520
    title: qsTr("Live Screen - iDescriptor")

    // readonly property int iosVersion: device.info.ios_version_major
    property int rotationDegrees: 0
    property bool mirrorHorizontal: false
    property string statusText: qsTr("Connecting to screenshot service...")

    function startInitialization(start) {
        statusText = qsTr("Connecting to screenshot service...")
        stateView.errorText = ""
        stateView.viewState = StateView.State.Loading
        if (start) {
            backend.start_capture()
        } else {
            Helpers.setTimeout(function() {
                devModeHelper.start()
            }, 200)
        }
    }

    function handleFailedInitialization(reason, need) {
        backend.stop_capture()

        if (need === "dev-img") {
            stateView.errorText = qsTr("Failed to initialize screenshot capture. Mount a compatible developer disk image, then retry.")
        } else if (need === "dev-mode") {
            stateView.errorText = qsTr("Failed to initialize screenshot capture. Please ensure the device has developer mode enabled.")
        } else {
            stateView.errorText = qsTr("Failed to initialize screenshot capture. Reason: %1").arg(reason)
        }

        stateView.viewState = StateView.State.Error
    }

    onClosing: backend.stop_capture()

    Component.onCompleted: startInitialization(false)

    DevModeHelper {
        id: devModeHelper
        device: root.device

        onHandled: function(success, forced) {
            if (success) {
                root.startInitialization(true)
            } else {
                stateView.errorText = root.iosVersion >= 17
                    ? qsTr("Developer Mode was not handled.")
                    : qsTr("Developer disk image was not mounted.")
                stateView.viewState = StateView.State.Error
            }
        }
    }

    //TODO: we could move this to service_factory.rs
    ScreenshotBackend {
        id: backend
        udid: root.udid
        ios_version: root.iosVersion

        onScreenshotCaptured: function(data) {
            console.log("Screenshot captured, size:", data.length)
            screenItem.set_frame(data)
            root.statusText = qsTr("Capturing")
            stateView.viewState = StateView.State.Content
        }

        onInitFailed: function(reason, need) {
            root.handleFailedInitialization(reason, need)
        }
    }

    StateView {
        id: stateView
        anchors.fill: parent
        autoSwitchContent: false
        retryable: true
        viewState: StateView.State.Loading
        onRetryRequested: {
            root.startInitialization(false)
        }

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: root.statusText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Rectangle {
                id: screenFrame
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: palette.base
                border.color: Qt.rgba(0, 0, 0, 0.18)
                border.width: 1
                clip: true

                Item {
                    id: viewport
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true

                    QmlImage {
                        id: screenItem
                        anchors.fill: parent
                        rotation_degrees: root.rotationDegrees
                        mirror_horizontal: root.mirrorHorizontal
                    }

                    Connections {
                        target: root
                        function onRotationDegreesChanged() {
                            screenItem.update_paint()
                        }

                        function onMirrorHorizontalChanged() {
                            screenItem.update_paint()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Button {
                    text: qsTr("Rotate CW")
                    onClicked: root.rotationDegrees = (root.rotationDegrees + 90) % 360
                }

                Button {
                    text: qsTr("Rotate CCW")
                    onClicked: root.rotationDegrees = (root.rotationDegrees + 270) % 360
                }

                Button {
                    text: root.mirrorHorizontal ? qsTr("Unmirror") : qsTr("Mirror")
                    checkable: true
                    checked: root.mirrorHorizontal
                    onToggled: root.mirrorHorizontal = checked
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
