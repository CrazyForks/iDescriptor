import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import "./base"

Dialog {
    id: root
    required property var device
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: parent

    width: 640
    height: 760
    // minimumWidth: 420
    // minimumHeight: 560
    visible: true
    // title: qsTr("Developer Mode - iDescriptor")

    function showError(message) {
        stateView.errorText = message
        stateView.viewState = StateView.State.Error
    }

    function revealDeveloperModeOption() {
        if (!root.device || !root.device.service_manager) {
            showError(qsTr("Something went wrong. No device service manager is available."))
            return
        }

        stateView.viewState = StateView.State.Loading

        Helpers.connectOnce(root.device.service_manager.developer_mode_option_revealed, function(revealed) {
            if (revealed) {
                startContentTimer.start()
            } else {
                showError(qsTr("Failed to reveal Developer Mode option in UI. Please try again later."))
            }
        })

        root.device.service_manager.reveal_developer_mode_option_in_ui()
    }

    Component.onCompleted: revealDeveloperModeOption()

    Timer {
        id: startContentTimer
        interval: 500
        repeat: false
        onTriggered: {
            stateView.viewState = StateView.State.Content
            tutorialVideo.play()
        }
    }

    StateView {
        id: stateView
        anchors.fill: parent
        autoSwitchContent: false
        retryable: true
        errorText: qsTr("Failed to reveal Developer Mode option in UI. Please try again later.")
        onRetryRequested: root.revealDeveloperModeOption()

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 20
            spacing: 0

            Label {
                Layout.fillWidth: true
                text: qsTr("Enable Developer Mode on your iOS device")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 18
                font.bold: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    text: qsTr("In order to use this feature on your device, you need to enable Developer Mode in the Settings app.\nThis allows iDescriptor to access additional features on your device.\nPlease follow the instructions in the video below to enable Developer Mode.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            Video {
                id: tutorialVideo
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 300
                source: "qrc:/resources/dev-mode.mp4"
                fillMode: VideoOutput.PreserveAspectFit
                loops: MediaPlayer.Infinite
                onVisibleChanged: {
                    if (visible && stateView.viewState === StateView.State.Content)
                        play()
                    else
                        pause()
                }
            }
        }
    }
}
