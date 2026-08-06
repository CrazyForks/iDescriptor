// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "./base"

AnimatedDialog {
    id: dialog

    required property int fileCount
    required property int folderCount

    signal confirmed()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(480, parent ? parent.width - 40 : 480)
    modal: true
    focus: true
    title: qsTr("Confirm Deletion")
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    readonly property bool containsFolders: folderCount > 0

    contentItem: ColumnLayout {
        spacing: 16

        Label {
            Layout.fillWidth: true
            text: dialog.containsFolders
                ? qsTr("Permanently delete %1 file(s) and %2 folder(s)? All contents inside the selected folders will also be deleted.")
                    .arg(dialog.fileCount).arg(dialog.folderCount)
                : qsTr("Permanently delete %1 file(s)?").arg(dialog.fileCount)
            color: App.Theme.text
            wrapMode: Text.WordWrap
            font.pixelSize: 14
        }

        CheckBox {
            id: recursiveConfirmation

            Layout.fillWidth: true
            visible: dialog.containsFolders
            text: qsTr("I understand.")
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("This action cannot be undone.")
            color: App.Theme.dangerText
            wrapMode: Text.WordWrap
            font.pixelSize: 13
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Cancel")
                onClicked: dialog.reject()
            }

            Button {
                text: qsTr("Delete")
                enabled: !dialog.containsFolders || recursiveConfirmation.checked

                contentItem: Label {
                    text: parent.text
                    color: parent.enabled ? App.Theme.dangerText : App.Theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    dialog.confirmed()
                    dialog.accept()
                }
            }
        }
    }
}
