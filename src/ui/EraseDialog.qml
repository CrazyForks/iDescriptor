// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"
import "." as App

AnimatedDialog {
    id: dialog

    required property string udid
    required property string displayName
    required property string backupRoot

    readonly property int firstConfirmation: 0
    readonly property int secondConfirmation: 1
    readonly property int resultPage: 2

    property int confirmationStep: firstConfirmation
    property bool operationStarted: false
    property bool operationInProgress: false
    property bool operationSucceeded: false
    readonly property bool dismissalLocked: operationStarted && !operationSucceeded

    modal: true
    focus: true
    standardButtons: Dialog.NoButton
    closePolicy: Popup.NoAutoClose
    width: Math.min(parent ? parent.width - 48 : 500, 500)
    height: 330
    padding: 24

    function resetFlow() {
        confirmationStep = firstConfirmation
        operationStarted = false
        operationInProgress = false
        operationSucceeded = false
        stateView.errorText = qsTr("The device could not be erased. Keep it connected and try again.")
        stateView.viewState = StateView.State.Loading
    }

    function requestClose() {
        if (!operationStarted || operationSucceeded)
            dialog.close()
    }

    function startErase() {
        if (!udid || operationInProgress || operationSucceeded)
            return

        confirmationStep = resultPage
        operationStarted = true
        operationInProgress = true
        stateView.viewState = StateView.State.Loading
        backupManager.erase_device(backupRoot, udid)
    }

    onOpened: resetFlow()

    Keys.onEscapePressed: function(event) {
        dialog.requestClose()
        event.accepted = true
    }

    Connections {
        target: backupManager

        function onOperationFinished(operation, operationUdid, success, errorCode, errorString) {
            if (operation !== "erase" || operationUdid !== dialog.udid || !dialog.operationStarted)
                return

            dialog.operationInProgress = false
            if (success) {
                dialog.operationSucceeded = true
                stateView.viewState = StateView.State.Content
            } else {
                stateView.errorText = errorString || qsTr("iDescriptor could not erase %1. Keep the device connected and try again.")
                    .arg(dialog.displayName || dialog.udid)
                stateView.viewState = StateView.State.Error
            }
        }
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, App.Theme.darkMode ? 0.52 : 0.30)
    }

    contentItem: ColumnLayout {
        spacing: 16

        Label {
            Layout.fillWidth: true
            text: dialog.operationInProgress
                ? qsTr("Erasing %1").arg(dialog.displayName || dialog.udid)
                : dialog.operationSucceeded
                    ? qsTr("Erase Command Accepted")
                    : qsTr("Erase %1?").arg(dialog.displayName || dialog.udid)
            color: App.Theme.text
            font.pixelSize: 20
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        StateView {
            id: stateView
            Layout.fillWidth: true
            Layout.fillHeight: true
            autoSwitchContent: !dialog.operationStarted
            autoSwitchDelay: 250
            retryable: dialog.operationStarted && !dialog.operationInProgress && !dialog.operationSucceeded
            cancelable: false
            retryText: qsTr("Try Again")
            onRetryRequested: dialog.startErase()

            contentItem: StackLayout {
                anchors.fill: parent
                currentIndex: dialog.confirmationStep

                ColumnLayout {
                    spacing: 18

                    Item { Layout.fillHeight: true }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("This will erase all content and settings from %1. This action cannot be undone. Do you want to continue?")
                            .arg(dialog.displayName || dialog.udid)
                        color: App.Theme.text
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10

                        Button {
                            text: qsTr("No")
                            onClicked: dialog.requestClose()
                        }

                        Button {
                            text: qsTr("Yes")
                            palette.buttonText: App.Theme.dangerText
                            onClicked: dialog.confirmationStep = dialog.secondConfirmation
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    spacing: 18

                    Item { Layout.fillHeight: true }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Are you absolutely sure you want to permanently erase %1?")
                            .arg(dialog.displayName || dialog.udid)
                        color: App.Theme.dangerText
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10

                        Button {
                            text: qsTr("No")
                            onClicked: dialog.requestClose()
                        }

                        Button {
                            text: qsTr("Yes, Erase Device")
                            palette.buttonText: App.Theme.dangerText
                            onClicked: dialog.startErase()
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    spacing: 14

                    Item { Layout.fillHeight: true }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("The erase command completed successfully. The device will restart and remove all content and settings.")
                        color: App.Theme.text
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Close")
                        enabled: dialog.operationSucceeded
                        highlighted: true
                        onClicked: dialog.requestClose()
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
