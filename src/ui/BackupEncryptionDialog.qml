import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"
import "." as App

AnimatedDialog {
    id: dialog

    required property string udid
    required property string deviceName
    required property string backupRoot

    readonly property bool dismissalLocked: submitting
    property bool encryptionEnabled: false
    property bool statusResolved: false
    property bool submitting: false
    property bool passcodeRequested: false
    property string inlineError: ""

    signal encryptionConfigured()

    modal: true
    focus: true
    title: encryptionEnabled
           ? qsTr("Change Backup Password")
           : qsTr("Enable Encrypted Backups")
    standardButtons: Dialog.NoButton
    closePolicy: submitting
                 ? Popup.NoAutoClose
                 : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Math.min(parent ? parent.width - 48 : 520, 520)
    height: 580
    padding: 24

    function queryStatus() {
        statusResolved = false
        submitting = false
        passcodeRequested = false
        inlineError = ""
        stateView.viewState = StateView.State.Loading
        backupManager.get_backup_encryption_status(udid)
    }

    function submit() {
        if (submitting || !statusResolved)
            return

        if (encryptionEnabled && currentPassword.text.length === 0) {
            inlineError = qsTr("Enter the current backup password.")
            currentPassword.forceActiveFocus()
            return
        }
        if (newPassword.text.length === 0) {
            inlineError = qsTr("Enter a new backup password.")
            newPassword.forceActiveFocus()
            return
        }
        if (newPassword.text !== confirmPassword.text) {
            inlineError = qsTr("The new passwords do not match.")
            confirmPassword.forceActiveFocus()
            return
        }
        if (!passwordSavedCheck.checked) {
            inlineError = qsTr("Confirm that you have saved the password somewhere safe.")
            return
        }

        inlineError = ""
        submitting = true
        backupManager.change_backup_password(
            backupRoot,
            udid,
            encryptionEnabled ? currentPassword.text : "",
            newPassword.text)
    }

    function clearPasswords() {
        currentPassword.text = ""
        newPassword.text = ""
        confirmPassword.text = ""
        passwordSavedCheck.checked = false
    }

    onOpened: {
        clearPasswords()
        queryStatus()
    }
    onClosed: {
        clearPasswords()
        inlineError = ""
        passcodeRequested = false
    }

    Connections {
        target: backupManager

        function onBackupEncryptionStatusReady(operationUdid, success, enabled, errorString) {
            if (operationUdid !== dialog.udid || dialog.statusResolved)
                return

            if (!success) {
                stateView.errorText = errorString
                    || qsTr("The device's backup encryption status could not be read.")
                stateView.viewState = StateView.State.Error
                return
            }

            dialog.encryptionEnabled = enabled
            dialog.statusResolved = true
            stateView.viewState = StateView.State.Content
        }

        function onBackupEncryptionFinished(operationUdid, success, enabled, errorString) {
            if (operationUdid !== dialog.udid || !dialog.submitting)
                return

            dialog.submitting = false
            dialog.passcodeRequested = false
            if (!success || !enabled) {
                dialog.inlineError = errorString
                    || qsTr("Encrypted backups could not be enabled.")
                return
            }

            dialog.encryptionEnabled = true
            dialog.clearPasswords()
            dialog.encryptionConfigured()
            dialog.close()
        }

        function onBackupPasscodeChanged(operationUdid, requested) {
            if (operationUdid === dialog.udid && dialog.submitting)
                dialog.passcodeRequested = requested
        }
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, App.Theme.darkMode ? 0.52 : 0.30)
    }

    contentItem: StateView {
        id: stateView
        autoSwitchContent: false
        retryable: true
        retryText: qsTr("Try Again")
        onRetryRequested: dialog.queryStatus()

        contentItem: ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: stateView.width
                spacing: 14

                Label {
                    Layout.fillWidth: true
                    text: dialog.encryptionEnabled
                          ? qsTr("Encrypted backups are enabled for %1. Enter the current password to replace it.").arg(dialog.deviceName)
                          : qsTr("iDescriptor requires encrypted backups by default. Choose a password before backing up %1.").arg(dialog.deviceName)
                    color: App.Theme.text
                    wrapMode: Text.WordWrap
                }

                Frame {
                    Layout.fillWidth: true
                    padding: 12

                    background: Rectangle {
                        radius: 8
                        color: Qt.rgba(1, 0.59, 0, App.Theme.darkMode ? 0.14 : 0.10)
                        border.color: Qt.rgba(1, 0.59, 0, 0.45)
                    }

                    contentItem: Label {
                        text: qsTr("iDescriptor never stores this password. If you lose it, this and future encrypted backups cannot be restored. Changing or resetting the device's backup password does not unlock older backups.")
                        color: App.Theme.text
                        wrapMode: Text.WordWrap
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: dialog.passcodeRequested
                    text: qsTr("Enter the device passcode on the device to continue.")
                    color: App.Theme.systemOrange
                    wrapMode: Text.WordWrap
                }

                TextField {
                    id: currentPassword
                    Layout.fillWidth: true
                    visible: dialog.encryptionEnabled
                    enabled: !dialog.submitting
                    echoMode: TextInput.Password
                    placeholderText: qsTr("Current backup password")
                    onAccepted: newPassword.forceActiveFocus()
                }

                TextField {
                    id: newPassword
                    Layout.fillWidth: true
                    enabled: !dialog.submitting
                    echoMode: TextInput.Password
                    placeholderText: qsTr("New backup password")
                    onAccepted: confirmPassword.forceActiveFocus()
                }

                TextField {
                    id: confirmPassword
                    Layout.fillWidth: true
                    enabled: !dialog.submitting
                    echoMode: TextInput.Password
                    placeholderText: qsTr("Confirm new backup password")
                    onAccepted: dialog.submit()
                }

                CheckBox {
                    id: passwordSavedCheck
                    Layout.fillWidth: true
                    enabled: !dialog.submitting
                    text: qsTr("I have saved this password somewhere safe")
                }

                Label {
                    Layout.fillWidth: true
                    visible: dialog.inlineError.length > 0
                    text: dialog.inlineError
                    color: App.Theme.systemRed
                    wrapMode: Text.WordWrap
                }

                ProgressBar {
                    Layout.fillWidth: true
                    visible: dialog.submitting
                    indeterminate: true
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Button {
                        text: qsTr("Cancel")
                        enabled: !dialog.submitting
                        onClicked: dialog.close()
                    }

                    Button {
                        text: dialog.encryptionEnabled
                              ? qsTr("Change Password")
                              : qsTr("Enable Encryption")
                        highlighted: true
                        enabled: !dialog.submitting
                                 && newPassword.text.length > 0
                                 && confirmPassword.text.length > 0
                                 && (!dialog.encryptionEnabled || currentPassword.text.length > 0)
                                 && passwordSavedCheck.checked
                        onClicked: dialog.submit()
                    }
                }
            }
        }
    }
}
