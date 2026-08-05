// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma Singleton

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"

Item {
    id: root

    property var pendingWindow: null
    property string pendingScope: ""
    property string activeCategory: ""
    property var approvedCategories: []
    property bool retryCloseAfterDialog: false

    function scopeIncludes(scope, category) {
        return scope === "*" || scope === category
    }

    function categoryWasApproved(category) {
        return root.approvedCategories.indexOf(category) !== -1
    }

    function nextActiveCategory(scope) {
        if (root.scopeIncludes(scope, "backup")
                && !root.categoryWasApproved("backup")
                && backupManager.has_active_tasks())
            return "backup"

        if (root.scopeIncludes(scope, "io_manager")
                && !root.categoryWasApproved("io_manager")
                && ioManager.has_active_tasks())
            return "io_manager"

        return ""
    }

    function resetPendingClose() {
        root.pendingWindow = null
        root.pendingScope = ""
        root.activeCategory = ""
        root.approvedCategories = []
        root.retryCloseAfterDialog = false
    }

    function handler(scope, closeEvent, targetWindow) {
        // A second close request can arrive while another window owns the prompt.
        if (closingDialog.visible) {
            closeEvent.accepted = false
            return true
        }

        const continuingClose = root.pendingWindow === targetWindow
            && root.pendingScope === scope
        if (!continuingClose)
            root.approvedCategories = []

        const category = root.nextActiveCategory(scope)
        if (category === "") {
            if (root.pendingWindow === targetWindow)
                root.resetPendingClose()
            return false
        }

        // Returning from onClosing does not reject a close request. The event must be vetoed.
        closeEvent.accepted = false

        root.pendingWindow = targetWindow
        root.pendingScope = scope
        root.activeCategory = category
        root.retryCloseAfterDialog = false
        closingDialog.parent = targetWindow.contentItem
        closingDialog.open()
        return true
    }

    function keepWorking() {
        root.retryCloseAfterDialog = false
        closingDialog.close()
    }

    function cancelCurrentCategory() {
        if (root.activeCategory === "backup")
            backupManager.cancel_all_operations()
        else if (root.activeCategory === "io_manager")
            ioManager.cancel_all_jobs()

        const approved = root.approvedCategories.slice()
        approved.push(root.activeCategory)
        root.approvedCategories = approved
        root.retryCloseAfterDialog = true
        closingDialog.close()
    }

    AnimatedDialog {
        id: closingDialog
        modal: true
        focus: true
        anchors.centerIn: parent
        width: Math.min(460, parent ? parent.width - 48 : 460)
        standardButtons: Dialog.NoButton
        closePolicy: Popup.CloseOnEscape

        onClosed: {
            if (!root.retryCloseAfterDialog) {
                root.resetPendingClose()
                return
            }

            root.retryCloseAfterDialog = false
            const targetWindow = root.pendingWindow
            Qt.callLater(function () {
                if (targetWindow)
                    targetWindow.close()
            })
        }

        contentItem: ColumnLayout {
            spacing: 16

            Label {
                Layout.fillWidth: true
                text: root.activeCategory === "backup"
                    ? qsTr("Backup Operations Are Running")
                    : qsTr("File Transfers Are Running")
                color: Theme.text
                font.pixelSize: 20
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                Layout.fillWidth: true
                text: {
                    if (root.activeCategory === "backup") {
                        return root.pendingScope === "*"
                            ? qsTr("A backup or restore is still in progress. Quitting now will cancel it. Do you want to cancel the active backup tasks and quit?")
                            : qsTr("A backup or restore is still in progress. Closing this window will cancel it. Do you want to cancel the active backup tasks and close?")
                    }

                    return root.pendingScope === "*"
                        ? qsTr("One or more file transfers are still in progress. Quitting now will cancel them. Do you want to cancel the active transfers and quit?")
                        : qsTr("One or more file transfers are still in progress. Closing this window will cancel them. Do you want to cancel the active transfers and close?")
                }
                color: Theme.textMuted
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.separator
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item { Layout.fillWidth: true }

                Button {
                    text: qsTr("Keep Working")
                    onClicked: root.keepWorking()
                }

                Button {
                    text: root.pendingScope === "*"
                        ? qsTr("Cancel Tasks and Quit")
                        : qsTr("Cancel Tasks and Close")
                    palette.buttonText: Theme.dangerText
                    onClicked: root.cancelCurrentCategory()
                }
            }
        }
    }
}
