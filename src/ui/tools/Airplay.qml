import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia

import iDescriptor 1.0
import org.freedesktop.gstreamer.Qt6GLVideoItem 1.0
import ".." as App
import "../base"

ToolWindow {
    id: root

    width: 900
    height: 600
    minimumWidth: 800
    minimumHeight: 560
    visible: true
    title: qsTr("AirPlay - iDescriptor")
    color: App.Theme.controlFill

    property bool serverRunning: false
    property bool clientConnected: false
    property bool tutorialVideoLoaded: false

    function startAirPlay() {
        const started = AirplayImp.init(video)
        if (!started) {
            stateView.errorText = qsTr("Failed to start AirPlay.")
            stateView.viewState = StateView.State.Error
            return
        }

        root.serverRunning = true
        stateView.viewState = StateView.State.Content
        tutorialLoadTimer.start()
    }

    Component.onCompleted: {
        App.Settings.loadSettings()
        initTimer.start()
    }

    onClosing: {
        tutorialVideo.stop()
        AirplayImp.cleanup()
    }

    Connections {
        target: AirplayImp

        function onConnection_change(connected) {
            console.log("AirPlay connection change:", connected)
            root.clientConnected = connected
            if (connected) {
                tutorialVideo.pause()
            } else if (root.tutorialVideoLoaded && tutorialPage.visible) {
                tutorialVideo.play()
            }
        }
    }

    Timer {
        id: initTimer
        interval: 450
        repeat: false
        onTriggered: root.startAirPlay()
    }

    Timer {
        id: tutorialLoadTimer
        interval: 250
        repeat: false
        onTriggered: root.tutorialVideoLoaded = true
    }

    StateView {
        id: stateView
        anchors.fill: parent
        viewState: StateView.State.Loading
        autoSwitchContent: false
        retryable: true
        errorText: qsTr("Failed to start AirPlay.")
        onRetryRequested: {
            viewState = StateView.State.Loading
            initTimer.restart()
        }

        contentItem: StackLayout {
            anchors.fill: parent
            currentIndex: root.clientConnected ? 1 : 0

            Item {
                id: tutorialPage

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            Layout.fillWidth: true
                            text: root.serverRunning
                                  ? qsTr("Waiting for device connection")
                                  : qsTr("Starting AirPlay Server...")
                            color: palette.text
                            font.pixelSize: 16
                            font.bold: true
                        }

                        BusyIndicator {
                            running: !root.clientConnected
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                        }

                        Button {
                            text: qsTr("Settings")
                            onClicked: App.Settings.open()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: App.Theme.softBg
                        border.color: App.Theme.softBgBorder
                        border.width: 1
                        radius: 10
                        clip: true

                        StackLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            currentIndex: root.tutorialVideoLoaded ? 1 : 0

                            ColumnLayout {
                                spacing: 10

                                Item { Layout.fillHeight: true }

                                BusyIndicator {
                                    Layout.alignment: Qt.AlignHCenter
                                    running: !root.tutorialVideoLoaded
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Loading AirPlay tutorial...")
                                    horizontalAlignment: Text.AlignHCenter
                                    color: palette.text
                                }

                                Item { Layout.fillHeight: true }
                            }

                            Video {
                                id: tutorialVideo
                                fillMode: VideoOutput.PreserveAspectFit
                                source: root.tutorialVideoLoaded ? "qrc:/resources/airplay-tutorial.mp4" : ""
                                loops: MediaPlayer.Infinite
                                muted: true
                                onVisibleChanged: {
                                    if (visible && root.tutorialVideoLoaded && !root.clientConnected)
                                        play()
                                    else
                                        pause()
                                }
                                onSourceChanged: {
                                    if (source && visible && !root.clientConnected)
                                        play()
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Open Control Center on your device, choose Screen Mirroring, then select iDescriptor@UxPlay.")
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: palette.text
                    }
                }
            }

            Item {
                id: streamingPage
                property bool hudVisible: false

                onVisibleChanged: {
                    if (visible) {
                        hudVisible = true
                        hideHudTimer.restart()
                    }
                }

                GstGLQt6VideoItem {
                    id: video
                    anchors.fill: parent
                    objectName: "videoItem"
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onPositionChanged: {
                        streamingPage.hudVisible = true
                        hideHudTimer.restart()
                    }
                }

                Rectangle {
                    id: streamingHud
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 18
                    height: hudLayout.implicitHeight + 18
                    radius: 8
                    color: Qt.rgba(0, 0, 0, 0.48)
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    border.width: 1
                    opacity: streamingPage.hudVisible || hudMouse.containsMouse ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: App.Theme.mediumAnimation
                            easing.type: Easing.OutCubic
                        }
                    }

                    MouseArea {
                        id: hudMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hideHudTimer.restart()
                    }

                    Timer {
                        id: hideHudTimer
                        interval: 5000
                        repeat: false
                        onTriggered: streamingPage.hudVisible = false
                    }

                    RowLayout {
                        id: hudLayout
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 10

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Device connected - receiving stream...")
                            color: "white"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Button {
                            visible: App.Settings.show_v4l2 && Qt.platform.os === "linux"
                            enabled: false
                            text: qsTr("V4L2")
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Virtual camera output is not available in the QML AirPlay renderer yet.")
                        }
                    }
                }
            }
        }
    }
}
