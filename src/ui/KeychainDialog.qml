import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import "./base"
import "." as App

AnimatedDialog {
    id: dialog

    modal: true
    focus: true
    standardButtons: Dialog.NoButton
    closePolicy: Popup.NoAutoClose
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 32 : 600, 600)
    height: Math.min(parent ? parent.height - 32 : 570, 570)

    signal continueRequested()
    signal skipRequested()

    function completeInitialization(loadSavedAccount) {
        if (dontShowAgain.checked)
            settingsManager.set_show_keychain_dialog(false)

        dialog.close()
        if (loadSavedAccount)
            dialog.continueRequested()
        else
            dialog.skipRequested()
    }

    onOpened: {
        dontShowAgain.checked = false
        playbackTimer.restart()
    }
    // Stop playback when the dialog closes.
    onClosed: keychainVideo.stop()

    // Auto-play when the dialog is ready.
    Timer {
        id: playbackTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (dialog.visible)
                keychainVideo.play()
        }
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, App.Theme.darkMode ? 0.48 : 0.28)
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        // Title label
        Label {
            Layout.fillWidth: true
            text: qsTr("Allow Keychain Access")
            color: App.Theme.text
            font.pixelSize: 24
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        // Description label
        Label {
            Layout.fillWidth: true
            text: qsTr("iDescriptor uses macOS Keychain to securely store and retrieve your Apple ID credentials. When macOS asks for access, choose \"Always Allow\" to avoid repeated prompts.")
            color: App.Theme.textMuted
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Video preview
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 180
            radius: 10
            color: App.Theme.softBg
            border.color: App.Theme.softBgBorder
            border.width: 1
            clip: true

            Video {
                id: keychainVideo
                anchors.fill: parent
                anchors.margins: 1
                source: "qrc:/resources/keychain.mp4"
                fillMode: VideoOutput.PreserveAspectFit
                // Loop the video
                loops: MediaPlayer.Infinite
                muted: true
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Your credentials remain protected by macOS and are only used for App Store sign-in.")
            color: App.Theme.textMuted
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: App.Theme.separator
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            CheckBox {
                id: dontShowAgain
                text: qsTr("Do not show this message again")
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Skip for Now")
                Layout.preferredHeight: 36
                onClicked: dialog.completeInitialization(false)
            }

            Button {
                text: qsTr("Continue")
                highlighted: true
                Layout.preferredHeight: 36
                onClicked: dialog.completeInitialization(true)
            }
        }
    }
}
