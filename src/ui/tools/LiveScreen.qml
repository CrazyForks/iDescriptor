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

    readonly property int iosVersion: device && device.info && device.info.ios_version_major !== undefined
                                      ? device.info.ios_version_major
                                      : 0
    property int tries: 0
    property int rotationDegrees: 0
    property bool mirrorHorizontal: false
    property bool devModeHandled: false
    property string statusText: qsTr("Connecting to screenshot service...")

    function startInitialization(delay) {
        statusText = qsTr("Connecting to screenshot service...")
        stateView.errorText = ""
        stateView.viewState = StateView.State.Loading
        initTimer.interval = delay || 200
        initTimer.restart()
    }

    function showDeveloperModeHelper() {
        devModeHelper.start()
        stateView.errorText = qsTr("Developer Mode is required before Live Screen can start. Enable Developer Mode on the device, then retry.")
        stateView.viewState = StateView.State.Error
    }

    function handleFailedInitialization(reason, need) {
        backend.stop_capture()

        if (need === "dev-img") {
            if (devModeHelper.visible)
                return

            root.statusText = qsTr("Developer disk image required...")
            stateView.viewState = StateView.State.Loading
            devDiskHelper.start()
            return
        }

        if (need === "dev-mode") {
            showDeveloperModeHelper()
            return
        }

        if (root.iosVersion < 17) {
            if (root.tries < 2) {
                root.tries += 1
                root.statusText = qsTr("Retrying screenshot service...")
                startInitialization(400)
                return
            }

            stateView.errorText = qsTr("Failed to initialize screenshot capture. Mount a compatible developer disk image, then retry.")
        } else {
            stateView.errorText = qsTr("Failed to initialize screenshot capture. Please ensure the device has developer mode enabled.")
        }

        stateView.viewState = StateView.State.Error
    }

    onClosing: backend.stop_capture()

    Component.onCompleted: startInitialization(200)

    Timer {
        id: initTimer
        repeat: false
        onTriggered: {
            if (iosVersion < 6) {
                stateView.errorText = qsTr("Live Screen is not supported on iOS versions below 6.")
                stateView.viewState = StateView.State.Error
                return
            } else if (iosVersion >= 17
                && root.device.info.developer_mode_enabled !== true
                && !root.devModeHandled) {
                showDeveloperModeHelper()
                return
            }

            backend.start_capture()
            root.statusText = qsTr("Capturing")
        }
    }

    DevModeHelper {
        id: devModeHelper
        device: root.device
        // udid: root.udid
        iosVersion: root.iosVersion

        onHandled: function(success, forced) {
            if (success) {
                root.devModeHandled = true
                root.tries = 0
                root.startInitialization(800)
            } else {
                stateView.errorText = root.iosVersion >= 17
                    ? qsTr("Developer Mode was not handled.")
                    : qsTr("Developer disk image was not mounted.")
                stateView.viewState = StateView.State.Error
            }
        }
    }

    ScreenshotBackend {
        id: backend
        udid: root.udid
        ios_version: root.iosVersion

        onScreenshot_captured: function(data) {
            screenItem.set_frame(data)
            root.statusText = qsTr("Capturing")
            stateView.viewState = StateView.State.Content
        }

        onInit_failed: function(reason, need) {
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
            root.tries = 0
            root.startInitialization(200)
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
