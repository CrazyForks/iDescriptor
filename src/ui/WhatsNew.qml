// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"
import "." as App

AnimatedDialog {
    id: root

    readonly property string currentVersion: settingsManager.current_version()
    property bool awaitingReleaseNotes: false
    property var releaseProfile: ({})
    property string releaseNotesError: ""

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Math.min(560, parent ? parent.width - 32 : 560)
    height: Math.min(540, parent ? parent.height - 32 : 540)

    function showIfNeeded() {
        if (settingsManager.app_version() === root.currentVersion)
            return

        // Match the original MainWindow behavior: remember the running version
        // before requesting its release notes so they are only shown once.
        settingsManager.set_app_version(root.currentVersion)
        root.awaitingReleaseNotes = true
        root.releaseProfile = ({})
        root.releaseNotesError = ""
        UpdaterImp.fetch_current_release()
    }

    function showReleaseNotes(profile) {
        if (!root.awaitingReleaseNotes)
            return

        root.awaitingReleaseNotes = false
        root.releaseProfile = profile || ({})
        root.open()
    }

    function showReleaseNotesError(message) {
        if (!root.awaitingReleaseNotes)
            return

        root.awaitingReleaseNotes = false
        root.releaseNotesError = message || qsTr("Failed to load release notes.")
        root.open()
    }

    Connections {
        target: UpdaterImp

        function onCurrentReleaseReady(profile) {
            root.showReleaseNotes(profile)
        }

        function onCurrentReleaseFailed(message) {
            root.showReleaseNotesError(message)
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 26
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: qsTr("iDescriptor has been updated to v%1").arg(root.currentVersion)
            color: App.Theme.text
            font.pixelSize: 22
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            visible: !!root.releaseProfile.release_name
            text: root.releaseProfile.release_name || ""
            color: App.Theme.textMuted
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 220
            radius: 14
            color: App.Theme.groupedBackground
            border.color: App.Theme.controlStroke
            border.width: 1

            ScrollView {
                anchors.fill: parent
                anchors.margins: 10
                clip: true

                TextArea {
                    width: parent.width
                    text: root.releaseNotesError
                          || root.releaseProfile.body
                          || qsTr("No release notes were provided for this version.")
                    textFormat: Text.MarkdownText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: Text.WordWrap
                    color: root.releaseNotesError ? App.Theme.dangerText : App.Theme.text
                    background: Rectangle { color: "transparent" }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                text: qsTr("Ok, Thanks!")
                onClicked: root.close()
            }

            Button {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                text: qsTr("Donate")
                highlighted: true
                font.bold: true
                onClicked: {
                    Qt.openUrlExternally(App.Constants.openCollectiveUrl)
                    root.close()
                }
            }
        }
    }
}
