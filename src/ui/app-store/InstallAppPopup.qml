import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../"
import "../base"

AnimatedDialog {
    id: root
    required property string bundleId
    required property string appName

    background: Rectangle {
        radius: 10
        color: palette.window
        border.color: Qt.rgba(0, 0, 0, 0.12)
        border.width: 1
    }
    padding: 20

    modal: true
    focus: true
    width: 500
    title: qsTr("Install IPA")
    standardButtons: Dialog.NoButton
    closePolicy: root.installing ? Popup.NoAutoClose : Popup.CloseOnPressOutside

    readonly property bool hasDevice: DeviceContext.devices.count > 0
    property int selectedDeviceIndex: hasDevice ? 0 : -1
    readonly property var selectedDevice:
        selectedDeviceIndex >= 0 && selectedDeviceIndex < DeviceContext.devices.count
        ? DeviceContext.devices.get(selectedDeviceIndex)
        : null
    property string taskId: ""
    property bool installing: false
    property real progress: 0
    property string stateText: ""
    property string errorText: ""
    property string resolvedAppName: ""
    readonly property string effectiveAppName: root.appName.length > 0
                                                ? root.appName
                                                : root.resolvedAppName

    function resolveAppName() {
        root.resolvedAppName = ""

        if (root.appName.length > 0 || root.bundleId.length === 0)
            return

        const requestedBundleId = root.bundleId
        Helpers.fetch_app_name(requestedBundleId, function(name) {
            // Ignore a response for an app that is no longer displayed.
            if (root.bundleId === requestedBundleId && root.appName.length === 0)
                root.resolvedAppName = name
        })
    }

    function resetState() {
        taskId = ""
        installing = false
        progress = 0
        stateText = ""
        errorText = ""
        selectedDeviceIndex = hasDevice ? 0 : -1
    }

    function requestClose() {
        if (installing) {
            cancelConfirmation.open()
            return
        }
        close()
    }

    function startInstall() {
        if (!selectedDevice)
            return

        errorText = ""
        progress = -1
        stateText = qsTr("Preparing IPA download...")

        const id = apps.install_app(bundleId, selectedDevice.udid)
        if (!id || !id.length) {
            progress = 0
            errorText = qsTr("The App Store service is not initialized.")
            stateText = errorText
            return
        }

        taskId = id
        installing = true
    }

    onOpened: {
        resetState()
        resolveAppName()
    }
    onClosed: {
        if (taskId.length)
            apps.cancel_task(taskId)
        taskId = ""
        installing = false
    }

    Keys.onEscapePressed: function(event) {
        root.requestClose()
        event.accepted = true
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    MessageDialog {
        id: cancelConfirmation
        title: qsTr("Cancel installation?")
        text: qsTr("The IPA download or installation is still in progress. Do you want to cancel it and close this dialog?")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button !== MessageDialog.Yes)
                return

            const id = root.taskId
            root.taskId = ""
            root.installing = false
            if (id.length)
                apps.cancel_task(id)
            root.close()
        }
    }

    Connections {
        target: apps

        function onInstallAppProgress(taskId, progress, phase) {
            if (taskId !== root.taskId)
                return

            root.installing = true
            root.progress = progress
            root.stateText = phase === "install"
                    ? qsTr("Installing IPA on device...")
                    : qsTr("Downloading IPA...")
        }

        function onInstallAppFinished(taskId, success, error) {
            if (taskId !== root.taskId)
                return

            root.taskId = ""
            root.installing = false
            root.progress = success ? 1 : 0
            root.errorText = success ? "" : (error || qsTr("Installation failed."))
            root.stateText = success ? qsTr("Installation finished") : root.errorText
        }
    }

    contentItem: StateView {
        viewState: root.effectiveAppName.length ? StateView.State.Content : StateView.State.Loading
        autoSwitchContent: false
        implicitHeight: installContent.implicitHeight

        contentItem: ColumnLayout {
            id: installContent
            anchors.fill: parent
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: root.effectiveAppName
                font.pixelSize: 18
                font.bold: true
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: root.bundleId
                color: "#6e6e73"
                elide: Text.ElideMiddle
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Select a connected device")
                font.bold: true
            }

            ComboBox {
                id: deviceCombo
                Layout.minimumWidth: 220
                Layout.preferredWidth: 220
                enabled: root.hasDevice && !root.installing
                model: DeviceContext.devices
                textRole: "text"
                valueRole: "udid"
                currentIndex: root.selectedDeviceIndex

                onActivated: function(index) {
                    root.selectedDeviceIndex = index
                }

                onCountChanged: {
                    if (count === 0)
                        root.selectedDeviceIndex = -1
                    else if (root.selectedDeviceIndex < 0 || root.selectedDeviceIndex >= count)
                        root.selectedDeviceIndex = 0
                }
            }

            Label {
                Layout.fillWidth: true
                visible: !root.hasDevice
                text: qsTr("No device connected.")
                color: "#6e6e73"
                wrapMode: Text.WordWrap
            }

            ProgressBar {
                Layout.fillWidth: true
                visible: root.installing || root.progress > 0
                indeterminate: root.installing && root.progress < 0
                from: 0
                to: 1
                value: Math.max(0, root.progress)
            }

            Label {
                Layout.fillWidth: true
                text: root.errorText.length ? root.errorText : root.stateText
                color: root.errorText.length ? "#c00" : "#6e6e73"
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    text: root.installing ? qsTr("Cancel") : qsTr("Close")
                    onClicked: root.requestClose()
                }

                Button {
                    text: qsTr("Install")
                    enabled: !root.installing && root.bundleId.length > 0 && root.selectedDevice
                    onClicked: root.startInstall()
                }
            }
        }
    }
}
