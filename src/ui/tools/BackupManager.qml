import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Dialogs
import QtQuick.Layouts
import "../base"
import "../" as App

ToolWindow {
    id: root
    width: 860
    height: 660
    minimumWidth: 740
    minimumHeight: 540
    title: qsTr("Backups - iDescriptor")

    property string backupRoot: settingsManager.mk_backup_root_path()
    readonly property var state: backupManager.state
    readonly property bool busy: backupManager.busy
    readonly property bool loading: state.loading
    property string selectedBackupUdid: ""
    property string selectedBackupSource: ""
    property string selectedBackupName: ""
    property bool selectedBackupEncrypted: false
    property string eraseUdid: ""
    property string eraseName: ""
    property var deviceBackupSections: ({})
    property var passwordWasSet: false


    function deviceName(device) {
        if (!device)
            return qsTr("Unknown")

        if (device.info && device.info.marketing_name)
            return device.info.marketing_name

        if (device.text)
            return device.text

        return device.udid || qsTr("Unknown")
    }

    function shortUdid(value) {
        if (!value || value.length <= 14)
            return value || ""
        return value.slice(0, 10) + "..."
    }

    function unknownBackupCount() {
        let total = 0
        for (let i = 0; i < backupManager.backup_model.count; ++i) {
            const item = backupManager.backup_model.get(i)
            if (!App.DeviceContext.getDevice(item.udid))
                total += 1
        }
        return total
    }


    function selectBackupForRestore(udid, title) {

        const metadata = backupManager.get_backup_metadata(udid, root.backupRoot)
        if (!metadata || !metadata.success) {
            //handle error somehow
            return
        }

        root.selectedBackupUdid = udid
        root.selectedBackupName = title || udid
        root.selectedBackupEncrypted = metadata.IsEncrypted
        root.passwordWasSet = metadata.WasPasscodeSet
        passwordField.text = ""
        encryptedBackup.checked = root.selectedBackupEncrypted
        restoreDialog.open()
    }


    function openBackupDetails(udid, title) {
        nav.push(detailsHostComponent, {
            sectionUdid: udid,
            sectionTitle: title || udid
        })
    }

    function openBackupDetailsWithoutDevice(udid) {
        nav.push(detailsHostComponentWithoutDevice, {
            udid
        })
    }

    // function refreshBackups() {
    //     backupManager.refresh(backupRoot)
    // }

    function chooseBackupRoot(path) {
        backupRoot = path
        settingsManager.set_backup_root_path(path)
        refreshBackups()
    }

    Component.onCompleted: {
        backupManager.init(root.backupRoot)
        // refreshBackups()
    }

    onClosing: {
        // Prompt and cancel
        backupManager.cancel()
    }

    Connections {
        target: backupManager

        function onOperationFinished(operation, udid, success) {
            const section = root.deviceBackupSections[udid]
            if (!section)
                return

            // TODO: maybe show a toast or something
            section.handleReset()
        }

        function onProgressUpdate(udid, progress) {
            const section = root.deviceBackupSections[udid]
            if (!section)
                return

            section.updateProgress(progress)
        }


        function onFileReceived(udid, path) {
            const section = root.deviceBackupSections[udid]
            if (!section)
                return

            section.fileReceived(path)
        }
    }

    FolderDialog {
        id: backupRootDialog
        title: qsTr("Select Backup Directory")
        onAccepted: root.chooseBackupRoot(QmlUtils.url_to_path(selectedFolder))
    }

    Dialog {
        id: restoreDialog
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(460, root.width - 48)
        title: qsTr("Restore Backup")
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: {
            if (!root.selectedBackupUdid || !root.selectedBackupSource)
                return

            if (root.passwordWasSet && !passwordField.text) {
                // TODO: handle error
                return
            }

            backupManager.start_restore(
                root.backupRoot,
                root.selectedBackupUdid,
                root.selectedBackupSource,
                encryptedBackup.checked ? passwordField.text : "",
                rebootToggle.checked,
                copyToggle.checked,
                preserveToggle.checked,
                systemToggle.checked,
                removeToggle.checked
            )

            const section = root.deviceBackupSections[root.selectedBackupUdid]
            if (section) {
                section.isRestoring = true
                section.progress = 0
                section.cancelRequested = false
                section.lastFileReceivedPath = ""
            }
        }

        ColumnLayout {
            width: parent.width
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: qsTr("Restore “%1” to its matching device.").arg(root.selectedBackupName)
                color: App.Theme.text
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Restore Settings")
                    color: App.Theme.textMuted
                    font.pixelSize: 12
                    bottomPadding: 6
                }

                CheckBox {
                    id: rebootToggle
                    Layout.fillWidth: true
                    text: qsTr("Restart device after restore")
                    checked: true
                }

                CheckBox {
                    id: copyToggle
                    Layout.fillWidth: true
                    text: qsTr("Copy backup data")
                    checked: true
                }

                CheckBox {
                    id: preserveToggle
                    Layout.fillWidth: true
                    text: qsTr("Preserve settings")
                    checked: true
                }

                CheckBox {
                    id: systemToggle
                    Layout.fillWidth: true
                    text: qsTr("Restore system files")
                    checked: false
                }

                CheckBox {
                    id: removeToggle
                    Layout.fillWidth: true
                    text: qsTr("Remove items not restored")
                    checked: false
                }
            }

            CheckBox {
                id: encryptedBackup
                Layout.fillWidth: true
                text: qsTr("Encrypted Backup")
                checked: root.selectedBackupEncrypted
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                visible: root.passwordWasSet
                echoMode: TextInput.Password
                placeholderText: qsTr("Backup password")
            }
        }
    }

    Dialog {
        id: advancedDialog
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(460, root.width - 48)
        title: qsTr("Advanced")
        standardButtons: Dialog.Close

        ColumnLayout {
            width: parent.width
            spacing: 0

            Repeater {
                model: App.DeviceContext.devices

                ItemDelegate {
                    Layout.fillWidth: true
                    enabled: !root.busy
                    text: qsTr("Erase %1…").arg(root.deviceName(model))
                    palette.text: App.Theme.dangerText
                    onClicked: {
                        root.eraseUdid = model.udid
                        root.eraseName = root.deviceName(model)
                        advancedDialog.close()
                        eraseConfirmOne.open()
                    }
                }
            }
        }
    }

    Dialog {
        id: eraseConfirmOne
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(440, root.width - 48)
        title: qsTr("Erase Device")
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: eraseConfirmTwo.open()

        Label {
            width: parent.width
            text: qsTr("This will erase all content and settings from %1. This action cannot be undone.").arg(root.eraseName)
            color: App.Theme.text
            wrapMode: Text.WordWrap
        }
    }

    Dialog {
        id: eraseConfirmTwo
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(440, root.width - 48)
        title: qsTr("Confirm Erase")
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: backupManager.erase_device(root.backupRoot, root.eraseUdid)

        Label {
            width: parent.width
            text: qsTr("Confirm again to permanently erase this device.")
            color: App.Theme.dangerText
            wrapMode: Text.WordWrap
        }
    }

    Component {
        id: deviceBackupSection

        ColumnLayout {
            id: sectionRoot
            property bool backupExists:false
            property string sectionUdid: ""
            property string sectionTitle: ""
            property bool isBackingUp: false
            property bool isRestoring: false
            property real progress: 0.0
            property string lastFileReceivedPath: ""
            property bool cancelRequested: false


            signal detailsRequested(string udid, string title)

            function handleReset() {
                isBackingUp = false
                isRestoring = false
                progress = 0.0
                lastFileReceivedPath = ""
                cancelRequested = false
            }

            function updateProgress(value, time_remaining) {
                sectionRoot.progress = value
            }

            function fileReceived(path) {
                lastFileReceivedPath = "..." + path.slice(path.length - 20, path.length)
            }   

            Layout.fillWidth: true
            spacing: 0

            ItemDelegate {
                Layout.fillWidth: true
                implicitHeight: 56
                onClicked: {
                    if (sectionRoot.backupExists) {
                        sectionRoot.detailsRequested(sectionRoot.sectionUdid, sectionRoot.sectionTitle)
                    }
                } 
                

                contentItem : StackLayout {
                    currentIndex: sectionRoot.isBackingUp || sectionRoot.isRestoring ? 1 : 0

                    // Normal state
                    RowLayout {
                        anchors.fill: parent
                        spacing: 12


                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: sectionTitle
                                color: App.Theme.text
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: sectionRoot.backupExists ? qsTr("Backup exists") : qsTr("No backup")
                                color: App.Theme.textMuted
                                font.pixelSize: 12
                            }
                        }

                        Button {
                            text: !sectionRoot.backupExists ? qsTr("Back Up Now") : qsTr("Restore")
                            highlighted: true
                            enabled: !root.busy
                            onClicked: {
                                //warn if wireless
                                if (!sectionRoot.backupExists) {
                                    backupManager.start_backup(root.backupRoot, sectionUdid)
                                    sectionRoot.isBackingUp = true
                                } else {
                                    root.selectBackupForRestore(sectionRoot.sectionUdid, sectionRoot.sectionTitle)
                                }
                            }
                        }

                        Button {
                            visible: sectionRoot.backupExists
                            text: qsTr("Details")
                            highlighted: true
                            onClicked: {
                                sectionRoot.detailsRequested(sectionRoot.sectionUdid, sectionRoot.sectionTitle)
                            }
                        }
                    }

                    //Backup or Restore in progress state
                    RowLayout {
                        id: progressRow
                        anchors.fill: parent
                        spacing: 12


                        property string infoText: {
                            switch (true) {
                                case sectionRoot.cancelRequested:
                                    return qsTr("Cancelling…")
                                case sectionRoot.isBackingUp:
                                    if (sectionRoot.lastFileReceivedPath.length > 0) {
                                        return sectionRoot.lastFileReceivedPath
                                    } 
                                    return qsTr("Backing up…")
                                case sectionRoot.isRestoring:
                                    return qsTr("Restoring…")
                                default:
                                    return ""
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: sectionTitle
                            color: sectionRoot.cancelRequested ? App.Theme.textMuted : App.Theme.text
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: progressRow.infoText
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }

                        ProgressBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            from: 0
                            value: sectionRoot.progress
                            to: 1
                        }

                        Spinner {
                            running: true
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                        }

                        Button {
                            text: sectionRoot.cancelRequested ? qsTr("Cancelling…") : qsTr("Cancel")
                            highlighted: true
                            enabled: !sectionRoot.cancelRequested
                            onClicked: {
                                // FIXME: wireup
                                //prompt first
                                sectionRoot.cancelRequested = true
                                const cancelSuccess = backupManager.cancel_operation(sectionUdid)
                                if (cancelSuccess) {
                                    sectionRoot.handleReset()
                                } else {
                                    console.warn("Failed to cancel operation for udid:", sectionUdid)
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    StackView {
        id: nav
        anchors.fill: parent
        initialItem: mainPageComponent
        clip: true

        pushEnter: Transition {
            PropertyAnimation { property: "x"; from: root.width; to: 0; duration: 320; easing.type: Easing.OutCubic }
        }
        pushExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: -root.width; duration: 320; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 1; to: 0.55; duration: 320; easing.type: Easing.OutCubic }
        }
        popEnter: Transition {
            PropertyAnimation { property: "x"; from: -root.width; to: 0; duration: 280; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 0.55; to: 1; duration: 280; easing.type: Easing.OutCubic }
        }
        popExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: nav.width; duration: 280; easing.type: Easing.OutCubic }
        }
    }

    Component {
        id: mainPageComponent

        StateView {
            id: stateView
            anchors.fill: parent
            viewState: StateView.State.Loading

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Backups")
                    color: App.Theme.text
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Manage local backups for devices. You can back up, restore, and erase devices from this interface.")
                    color: App.Theme.textMuted
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: App.Theme.sidebarDivider
                }

                ItemDelegate {
                    Layout.fillWidth: true
                    implicitHeight: 54
                    enabled: !root.busy

                    contentItem: RowLayout {
                        spacing: 12

                        Label {
                            text: qsTr("Backup Location")
                            color: App.Theme.text
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.backupRoot
                            color: App.Theme.textMuted
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideMiddle
                        }

                        Button {
                            text: qsTr("Change…")
                            enabled: !root.busy
                            onClicked: backupRootDialog.open()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: App.Theme.sidebarDivider
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Backups")
                    color: App.Theme.textMuted
                    font.pixelSize: 12
                }

                Button {
                    text: qsTr("Refresh")
                    enabled: !root.loading && !root.busy
                    onClicked: {
                        backupManager.init(backupRoot)
                    }
                }
            }

            StateView {
                id: deviceListStateView
                Layout.fillHeight: true
                Layout.fillWidth: true
                autoSwitchContent: false
                autoSwitchDelay: 300
                requestedViewState: root.state.loading ? StateView.State.Loading : StateView.State.Content
                contentItem : Loader {
                    anchors.fill: parent
                    active: !root.state.loading
                    sourceComponent: ScrollView {   
                        id: backupsScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        anchors.fill: parent
                        clip: true
                        contentWidth: availableWidth

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Backups and connected devices will appear here")
                            color: palette.text
                            visible: App.DeviceContext.devices.count === 0 && backupManager.backup_model.rowCount() === 0                            
                        }

                        ColumnLayout {
                            width: backupsScroll.availableWidth
                            spacing: 15

                            ColumnLayout {
                                Layout.fillWidth: true
                                Repeater {

                                    model: App.DeviceContext.devices 
                                    Loader {
                                        id: deviceBackupLoader
                                        Layout.fillWidth: true
                                        width: parent.width
                                        sourceComponent: deviceBackupSection
                                        onLoaded: {
                                            item.sectionUdid = model.udid
                                            item.sectionTitle = model.info.marketing_name
                                            item.backupExists = backupManager.does_backup_exist_for_udid(model.udid)
                                            item.detailsRequested.connect(root.openBackupDetails)
                                            root.deviceBackupSections[model.udid] = item
                                        }
                                    }
                                }
                            }

                            //Unknown Devices
                            ColumnLayout {
                                Layout.fillWidth: true

                                Repeater {
                                    model: backupManager.backup_model

                                    delegate: ItemDelegate {
                                        Layout.fillWidth: true
                                        width: parent.width
                                        // FIXME: this can be handled better with O(1) lookup
                                        visible: !App.DeviceContext.getDevice(model.udid)
                                        height: visible ? implicitHeight : 0
                                        onClicked: {
                                            root.openBackupDetailsWithoutDevice(model.udid)
                                        }
                                        contentItem: Label {
                                            text: model.udid
                                            color: App.Theme.text
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                    }
                }
            }
        }
    }
    }

    Component {
        id: detailsHostComponent

        Item {
            id: itemRoot
            required property string sectionUdid
            required property string sectionTitle

            Loader {
                anchors.fill: parent
                sourceComponent: App.BackupDetails {
                    udid: itemRoot.sectionUdid
                    backupRoot: root.backupRoot
                    title: itemRoot.sectionTitle
                    onBackRequested: nav.pop()
                }
            }
        }
    }


    Component {
        id: detailsHostComponentWithoutDevice
        Item {
            id: itemRoot
            required property string udid
            Loader {
                anchors.fill: parent
                sourceComponent: App.BackupDetailsWithoutDevice {
                    udid: itemRoot.udid
                    backupRoot: root.backupRoot
                    onBackRequested: nav.pop()
                }
            }
        }
    }
}
