import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "./base"
import "." as App

Item {
    id: root

    required property string udid
    required property string backupRoot
    required property string title
    required property string iconPath
    required property bool wireless
    required property bool initialForceFullBackup

    readonly property int readyPhase: 0
    readonly property int runningPhase: 1
    readonly property int completedPhase: 2
    readonly property int failedPhase: 3
    readonly property int cancelledPhase: 4
    property int phase: readyPhase
    property string statusDetail: ""
    property int receivedFileCount: 0
    property bool passcodeRequested: false
    property bool backupEncryptionEnabled: false
    property bool backupEncryptionStatusResolved: false
    property bool checkingBackupEncryption: false
    property string backupEncryptionStatusError: ""
    readonly property int maxLogEntries: 500
    readonly property bool inProgress: phase === runningPhase
    readonly property bool interactionLocked: inProgress
    readonly property string deviceName: title || qsTr("This Device")
    readonly property string placeholderSource: {
        if (iconPath && iconPath.length > 0)
            return iconPath
        return "qrc:/resources/icons/iphone_gen1_placeholder.png"
    }

    signal backRequested()
    signal doneRequested()
    signal backupRootSelected(string path)
    signal backupFinished()
    signal detailsRequested()

    function requestBackup() {
        if (!root.backupRoot || backupManager.busy)
            return

        if (root.wireless) {
            App.Helpers.messageBox(
                root,
                qsTr("Back Up Over Wi-Fi?"),
                qsTr("Wireless backups can take longer and may stop if the connection changes. Keep the device nearby, connected to power, and on the same Wi-Fi network until the backup finishes."),
                MessageDialog.Yes | MessageDialog.No,
                function(button) {
                    if (button === MessageDialog.Yes)
                        root.startBackup()
                })
            return
        }

        root.startBackup()
    }

    function refreshBackupEncryptionStatus() {
        root.backupEncryptionStatusResolved = false
        root.checkingBackupEncryption = true
        root.backupEncryptionStatusError = ""
        backupManager.get_backup_encryption_status(root.udid)
    }

    function manageEncryption() {
        if (backupManager.busy)
            return
        encryptionDialog.open()
    }

    function startBackup() {
        if (!root.backupRoot || backupManager.busy)
            return

        fileLog.clear()
        root.receivedFileCount = 0
        root.passcodeRequested = false
        root.statusDetail = qsTr("Preparing the backup...")
        root.phase = root.runningPhase
        backupManager.start_backup(root.backupRoot, root.udid, forceFullBackupCheck.checked)
    }

    function cancelBackup() {
        if (!root.inProgress)
            return

        root.statusDetail = qsTr("Cancelling the backup...")
        const cancelled = backupManager.cancel_operation(root.udid)
        if (!cancelled) {
            root.statusDetail = qsTr("The backup could not be cancelled.")
            return
        }

        root.passcodeRequested = false
        root.phase = root.cancelledPhase
        root.statusDetail = qsTr("The backup was cancelled. Files already written may remain in the selected folder.")
    }

    function appendFile(path) {
        root.receivedFileCount += 1
        fileLog.append({ filePath: String(path) })
        if (fileLog.count > root.maxLogEntries)
            fileLog.remove(0, fileLog.count - root.maxLogEntries)
        fileLogView.positionViewAtEnd()
    }

    function headingText() {
        if (root.phase === root.runningPhase)
            return qsTr("Backing Up %1").arg(root.deviceName)
        if (root.phase === root.completedPhase)
            return qsTr("Backup Complete")
        if (root.phase === root.failedPhase)
            return qsTr("Backup Couldn't Be Completed")
        if (root.phase === root.cancelledPhase)
            return qsTr("Backup Cancelled")
        return qsTr("Back Up %1").arg(root.deviceName)
    }

    function descriptionText() {
        if (root.phase === root.runningPhase)
            return qsTr("Keep the device connected while iDescriptor securely copies its data.")
        if (root.phase === root.completedPhase)
            return qsTr("Your device was backed up successfully.")
        if (root.phase === root.failedPhase)
            return qsTr("iDescriptor was unable to finish this backup. Review the activity log and try again.")
        if (root.phase === root.cancelledPhase)
            return root.statusDetail
        return qsTr("Create a local backup of your device before making changes or transferring data.")
    }

    ListModel {
        id: fileLog
    }

    Connections {
        target: backupManager

        function onFileReceived(udid, path) {
            if (!root.inProgress || udid !== root.udid)
                return
            root.statusDetail = path
            root.appendFile(path)
        }

        function onBackupPasscodeChanged(udid, requested) {
            if (!root.inProgress || udid !== root.udid)
                return

            root.passcodeRequested = requested
            root.statusDetail = requested
                    ? qsTr("Enter the device passcode on the device to continue.")
                    : qsTr("Preparing the backup...")
        }

        function onBackupCancellationRequested(udid) {
            if (!root.inProgress || udid !== root.udid)
                return

            root.statusDetail = qsTr("The device requested that this backup be cancelled.")
        }

        function onBackupEncryptionStatusReady(udid, success, enabled, errorString) {
            if (udid !== root.udid || !root.checkingBackupEncryption)
                return

            root.checkingBackupEncryption = false
            if (!success) {
                root.backupEncryptionStatusError = errorString
                    || qsTr("The device's backup encryption status could not be read.")
                return
            }

            root.backupEncryptionEnabled = enabled
            root.backupEncryptionStatusResolved = true
            root.backupEncryptionStatusError = ""
        }

        function onOperationFinished(operation, udid, success, errorCode, errorString) {
            if (operation !== "backup" || udid !== root.udid)
                return

            if (success) {
                root.passcodeRequested = false
                root.phase = root.completedPhase
                root.statusDetail = qsTr("Saved to %1").arg(root.backupRoot)
                root.backupFinished()
            } else if (errorCode === -2) {
                root.passcodeRequested = false
                root.phase = root.cancelledPhase
                root.statusDetail = errorString || qsTr("The backup was cancelled from the device.")
            } else {
                root.passcodeRequested = false
                root.phase = root.failedPhase
                root.statusDetail = errorString || qsTr("The backup operation ended before it could be completed.")
            }
        }
    }

    FolderDialog {
        id: backupRootDialog
        title: qsTr("Select Backup Directory")
        currentFolder: App.Helpers.toFileUrl(root.backupRoot)
        onAccepted: root.backupRootSelected(QmlUtils.url_to_path(selectedFolder))
    }

    BackupEncryptionDialog {
        id: encryptionDialog
        anchors.centerIn: Overlay.overlay
        udid: root.udid
        deviceName: root.deviceName
        backupRoot: root.backupRoot

        onEncryptionConfigured: {
            root.backupEncryptionEnabled = true
            root.backupEncryptionStatusResolved = true
            root.backupEncryptionStatusError = ""
            App.Helpers.showInfo(root, qsTr("The encrypted backup password was updated."))
        }
    }

    Component.onCompleted: root.refreshBackupEncryptionStatus()

    StateView {
        id: stateView
        anchors.fill: parent
        viewState: StateView.State.Loading

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                IconToolButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    enabled: !root.interactionLocked
                    icon.source: "qrc:/resources/icons/material-symbols_arrow-left-alt.svg"
                    toolTipText: root.interactionLocked
                                 ? qsTr("A backup operation is in progress")
                                 : qsTr("Back")
                    onClicked: root.backRequested()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        text: root.headingText()
                        color: App.Theme.text
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.descriptionText()
                        color: App.Theme.textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }

                Item {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 150

                    Image {
                        anchors.fill: parent
                        source: root.placeholderSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: App.Theme.separator
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                LocationSelector {
                    Layout.fillWidth: true
                    labelText: qsTr("Backup Location")
                    location: root.backupRoot
                    changeVisible: !root.interactionLocked && root.phase !== root.completedPhase
                    changeEnabled: !backupManager.busy
                    onChangeRequested: backupRootDialog.open()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    visible: !root.inProgress && root.phase !== root.completedPhase

                    CheckBox {
                        id: backupEncryptionStatusCheck
                        text: root.checkingBackupEncryption
                              ? qsTr("Checking backup encryption…")
                              : root.backupEncryptionStatusResolved
                                ? qsTr("Backup encryption enabled")
                                : qsTr("Backup encryption status unavailable")
                        tristate: true
                        checkState: !root.backupEncryptionStatusResolved
                                    ? Qt.PartiallyChecked
                                    : root.backupEncryptionEnabled
                                      ? Qt.Checked
                                      : Qt.Unchecked
                        enabled: false
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: backupEncryptionStatusCheck.indicator.width
                                           + backupEncryptionStatusCheck.spacing
                        visible: !root.checkingBackupEncryption
                        text: {
                            if (root.backupEncryptionStatusError.length > 0)
                                return root.backupEncryptionStatusError
                            if (!root.backupEncryptionEnabled)
                                return qsTr("Use the Manage Encryption button to set up encrypted backups.")
                            return qsTr("Backups for this device are protected with a password.")
                        }
                        color: root.backupEncryptionStatusError.length > 0
                               ? App.Theme.systemRed
                               : App.Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    CheckBox {
                        id: forceFullBackupCheck
                        text: qsTr("Force full backup")
                        checked: root.initialForceFullBackup
                        enabled: !backupManager.busy
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: forceFullBackupCheck.indicator.width
                                           + forceFullBackupCheck.spacing
                        text: qsTr("Only change this if you know what you are doing. If not, just leave it as it is.")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.phase !== root.readyPhase
                    radius: 7
                    color: App.Theme.controlFill
                    border.color: App.Theme.controlStroke
                    border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: qsTr("Activity")
                                color: App.Theme.text
                                font.weight: Font.DemiBold
                            }

                            Item { Layout.fillWidth: true }

                            Label {
                                text: root.receivedFileCount === 1
                                      ? qsTr("1 item")
                                      : qsTr("%1 items").arg(root.receivedFileCount)
                                color: App.Theme.textMuted
                                font.pixelSize: 12
                            }
                        }

                        ListView {
                            id: fileLogView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: fileLog.count > 0
                            clip: true
                            model: fileLog
                            spacing: 3

                            delegate: Label {
                                id: filePathLabel
                                required property string filePath
                                width: ListView.view.width
                                text: filePath
                                color: App.Theme.textMuted
                                font.family: Qt.platform.os === "windows" ? "Consolas" : "Menlo"
                                font.pixelSize: 11
                                elide: Text.ElideMiddle

                                HoverHandler {
                                    id: filePathHover
                                }

                                ToolTip.visible: filePathHover.hovered
                                ToolTip.text: filePathLabel.filePath
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: fileLog.count === 0 && root.passcodeRequested
                            text: qsTr("Enter the device passcode on the device to continue the backup.")
                            color: App.Theme.systemOrange
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: fileLog.count === 0 && !root.passcodeRequested
                            text: qsTr("Logs will appear here as files are received from the device.")
                            color: App.Theme.textMuted
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                    visible: root.phase === root.readyPhase
                }
            }

            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                visible: root.interactionLocked
                indeterminate: root.interactionLocked
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: App.Theme.separator
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    visible: root.phase === root.failedPhase
                    text: root.statusDetail
                    color: App.Theme.systemRed
                    elide: Text.ElideRight
                }

                Item {
                    Layout.fillWidth: true
                    visible: root.phase !== root.failedPhase
                }

                Button {
                    visible: root.inProgress
                    text: qsTr("Cancel")
                    onClicked: root.cancelBackup()
                }

                Button {
                    visible: root.phase === root.completedPhase
                    text: qsTr("Show Details")
                    onClicked: root.detailsRequested()
                }

                Button {
                    visible: root.phase === root.completedPhase
                    text: Qt.platform.os === "osx" ? qsTr("Show in Finder") : qsTr("Show in Folder")
                    onClicked: Qt.openUrlExternally(App.Helpers.toFileUrl(root.backupRoot))
                }

                Button {
                    visible: root.phase === root.completedPhase
                    text: qsTr("Done")
                    highlighted: true
                    onClicked: root.doneRequested()
                }

                Button {
                    visible: root.phase === root.readyPhase
                          || root.phase === root.failedPhase
                          || root.phase === root.cancelledPhase
                    text: qsTr("Manage Encryption…")
                    enabled: !backupManager.busy
                    onClicked: root.manageEncryption()
                }

                Button {
                    visible: root.phase === root.readyPhase
                          || root.phase === root.failedPhase
                          || root.phase === root.cancelledPhase
                    text: root.phase === root.readyPhase ? qsTr("Back Up Now") : qsTr("Try Again")
                    highlighted: true
                    enabled: root.backupRoot.length > 0
                             && !backupManager.busy
                    onClicked: root.requestBackup()
                }
            }
        }
    }
}
