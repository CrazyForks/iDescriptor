import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import iDescriptor 1.0
import "../base"

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
    property string imageSource: ""
    property string statusText: qsTr("Connecting to screenshot service...")

    function startInitialization(delay) {
        statusText = qsTr("Connecting to screenshot service...")
        stateView.errorText = ""
        stateView.viewState = StateView.State.Loading
        initTimer.interval = delay || 200
        initTimer.restart()
    }

    function handleFailedInitialization(reason) {
        backend.stop_capture()

        if (root.iosVersion < 17) {
            if (root.tries < 2) {
                root.tries += 1
                root.statusText = qsTr("Retrying screenshot service...")
                startInitialization(400)
                return
            }

            // FIXME: The QWidget version used DevDiskImageHelper to mount a developer
            // disk image here before retrying. QML currently exposes DevDiskImages.qml
            // and ServiceManager.mount_dev_image, but not the helper's automatic
            // version selection/download/mount flow.
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
            backend.start_capture()
            root.statusText = qsTr("Capturing")
        }
    }

    ScreenshotBackend {
        id: backend
        udid: root.udid
        ios_version: root.iosVersion

        onScreenshot_captured: function(dataUrl) {
            root.imageSource = dataUrl
            root.statusText = qsTr("Capturing")
            stateView.viewState = StateView.State.Content
        }

        onInit_failed: function(reason) {
            root.handleFailedInitialization(reason)
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

                    Image {
                        id: screenImage
                        readonly property bool rotatedSideways: root.rotationDegrees === 90 || root.rotationDegrees === 270

                        anchors.centerIn: parent
                        width: rotatedSideways ? viewport.height : viewport.width
                        height: rotatedSideways ? viewport.width : viewport.height
                        source: root.imageSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        rotation: root.rotationDegrees

                        transform: Scale {
                            origin.x: screenImage.width / 2
                            origin.y: screenImage.height / 2
                            xScale: root.mirrorHorizontal ? -1 : 1
                            yScale: 1
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
