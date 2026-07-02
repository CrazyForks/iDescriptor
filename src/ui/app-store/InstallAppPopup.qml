import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../" as App

Dialog {
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
    width: 500
    title: qsTr("Install IPA")
    standardButtons: Dialog.NoButton
    closePolicy: installing ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

    property string ipaPath: ""
    property int selectedDeviceIndex: App.DeviceContext.devices.count > 0 ? 0 : -1
    property var selectedDevice: selectedDeviceIndex >= 0 && selectedDeviceIndex < App.DeviceContext.devices.count
                                 ? App.DeviceContext.devices.get(selectedDeviceIndex)
                                 : null
    property bool installing: false
    property real progress: 0
    property string stateText: ""
    property string errorText: ""

    FileDialog {
        id: ipaDialog
        title: qsTr("Choose IPA")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("IPA files (*.ipa)"), qsTr("All files (*)")]
        onAccepted: root.ipaPath = QmlUtils.url_to_path(selectedFile)
    }

    Connections {
        target: root.selectedDevice ? root.selectedDevice.service_manager : null

        function onInstall_ipa_init(started, state) {
            root.installing = started
            root.stateText = state
            root.errorText = started ? "" : state
            if (!started)
                root.progress = 0
        }

        function onInstall_ipa_progress(progress, state) {
            root.installing = progress < 1
            root.progress = progress
            root.stateText = state
            if (progress >= 1)
                root.stateText = qsTr("Installation finished")
        }
    }

    contentItem: ColumnLayout {
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: root.appName
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
            enabled: root.hasDevice

            model: root.hasDevice ? App.DeviceContext.devices : [{ text: qsTr("No device connected"), udid: "" }]
            textRole: "text"
            valueRole: "udid"

            onActivated: (index) => {
                //fixme
            }

            onCountChanged: {
                //fixme
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: root.ipaPath.length ? root.ipaPath : qsTr("Choose a local IPA file")
                color: "#6e6e73"
                elide: Text.ElideMiddle
            }

            Button {
                text: qsTr("Choose")
                enabled: !root.installing
                onClicked: ipaDialog.open()
            }
        }

        ProgressBar {
            Layout.fillWidth: true
            visible: root.installing || root.progress > 0
            from: 0
            to: 1
            value: root.progress
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
                text: root.installing ? qsTr("Installing...") : qsTr("Cancel")
                enabled: !root.installing
                onClicked: root.close()
            }

            Button {
                text: qsTr("Install")
                enabled: !root.installing && root.ipaPath.length > 0 && root.selectedDevice
                onClicked: {
                    root.errorText = ""
                    root.progress = 0
                    root.stateText = qsTr("Preparing installation...")
                    root.installing = true
                    root.selectedDevice.service_manager.install_ipa(root.ipaPath)
                }
            }
        }
    }
}
