import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../base"
import "../"

ToolWindow {
    id: root
    width: 560
    height: 360
    minimumWidth: 420
    minimumHeight: 300
    title: qsTr("iFuse Mount - iDescriptor")

    property string selectedUdid: ""
    property string mountPath: ""
    property bool openedCurrentMount: false
    readonly property bool hasUsbDevice: usbDeviceModel.count > 0

    ListModel { id: usbDeviceModel }

    function isWirelessDevice(dev) {
        return dev && dev.info && dev.info.connection_type === "Wireless"
    }

    function deviceName(dev) {
        if (!dev)
            return qsTr("Unknown Device")
        if (dev.info && dev.info.product_type)
            return dev.info.product_type
        return dev.text || qsTr("Unknown Device")
    }

    function rebuildDeviceModel() {
        usbDeviceModel.clear()

        for (let i = 0; i < DeviceContext.devices.count; ++i) {
            const dev = DeviceContext.devices.get(i)
            if (isWirelessDevice(dev))
                continue // Skip wireless devices since ifuse only works with USB

            usbDeviceModel.append({
                udid: dev.udid,
                text: deviceName(dev) + " / " + dev.udid,
                productType: deviceName(dev)
            })
        }

        if (usbDeviceModel.count === 0) {
            selectedUdid = ""
            mountPath = qsTr("No device connected.")
            stateView.viewState = StateView.State.Content
            return
        }

        let index = 0
        for (let j = 0; j < usbDeviceModel.count; ++j) {
            if (usbDeviceModel.get(j).udid === root.udid) {
                index = j
                break
            }
        }

        deviceCombo.currentIndex = index
        applyDeviceAt(index)
        stateView.viewState = StateView.State.Content

        console.log(usbDeviceModel.count + " USB device(s) found.")
    }

    function applyDeviceAt(index) {
        if (index < 0 || index >= usbDeviceModel.count)
            return

        const item = usbDeviceModel.get(index)
        selectedUdid = item.udid
        mountPath = iFuse.default_mount_path(item.productType)
    }

    
    Component.onCompleted: {
        // FIXME: skipped WinFsp DiagnoseDialog check from QWidget port.
        // The original code showed DiagnoseDialog when IsWinFspInstalled() != SERVICE_AVAILABLE on Windows.
        rebuildDeviceModel()
    }

    Connections {
        target: DeviceContext.devices
        function onCountChanged() {
            root.rebuildDeviceModel()
        }
    }

    FolderDialog {
        id: linuxFolderDialog
        title: qsTr("Select Mount Directory")
        currentFolder: root.mountPath ? Helpers.toFileUrl(root.mountPath) : ""
        onAccepted: root.mountPath = QmlUtils.url_to_path(selectedFolder)
    }

    FileDialog {
        id: windowsMountDialog
        title: qsTr("Select Mount Directory")
        fileMode: FileDialog.SaveFile
        currentFolder: root.mountPath ? Helpers.toFileUrl(root.mountPath.substring(0, root.mountPath.lastIndexOf("/"))) : ""
        onAccepted: root.mountPath = QmlUtils.url_to_path(selectedFile)
    }

    StateView {
        id: stateView
        anchors.fill: parent
        viewState: StateView.State.Loading

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15

            // Description label
            Label {
                Layout.fillWidth: true
                text: qsTr("This tool allows you to mount your iPhone's disk as a drive on your PC")
                wrapMode: Text.WordWrap
                font.pixelSize: 14
                opacity: 0.72
                bottomPadding: 10
            }

            // Status label
            Rectangle {
                Layout.fillWidth: true
                visible: iFuse.state.message && iFuse.state.message.length > 0
                radius: 4
                color: iFuse.state.isError ? "#ffe6e6" : "#e6ffe6"
                border.color: iFuse.state.isError ? "#ffcccc" : "#ccffcc"
                implicitHeight: statusLabel.implicitHeight + 16

                Label {
                    id: statusLabel
                    anchors.fill: parent
                    anchors.margins: 8
                    text: iFuse.state.message || ""
                    color: iFuse.state.isError ? "#dd0000" : "#006600"
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Device selection
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Select Device:")
                    Layout.minimumWidth: 100
                }

                ComboBox {
                    id: deviceCombo
                    Layout.fillWidth: true
                    enabled: root.hasUsbDevice && !iFuse.state.busy
                    model: usbDeviceModel
                    textRole: "text"
                    valueRole: "udid"
                    onActivated: (index) => root.applyDeviceAt(index)
                }
            }

            // Mount path selection
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 35
                    radius: 4
                    border.color: "#cccccc"
                    color: "transparent"

                    Label {
                        anchors.fill: parent
                        anchors.margins: 8
                        text: root.mountPath || qsTr("Mount directory will be shown here")
                        elide: Text.ElideMiddle
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.mountPath && !iFuse.state.busy)
                                Qt.openUrlExternally(Helpers.toFileUrl(root.mountPath))
                        }
                    }
                }

                Button {
                    text: qsTr("Browse...")
                    enabled: root.hasUsbDevice && !iFuse.state.busy
                    onClicked: {
                        if (Qt.platform.os === "windows")
                            windowsMountDialog.open()
                        else
                            linuxFolderDialog.open()
                    }
                }
            }

            // Mount button
            Button {
                Layout.fillWidth: true
                implicitHeight: 40
                text: iFuse.state.busy ? qsTr("Mounting...") : qsTr("Mount Device")
                enabled: root.hasUsbDevice && !iFuse.state.busy
                onClicked: iFuse.mount(root.selectedUdid, root.mountPath)
            }

            Item { Layout.fillHeight: true }
        }
    }

    Connections {
        target: iFuse
        function onState_changed() {
            if (!iFuse.state.mounted)
                root.openedCurrentMount = false

            if (iFuse.state.mounted && !iFuse.state.busy && iFuse.state.mountPath && !root.openedCurrentMount) {
                root.openedCurrentMount = true
                Qt.openUrlExternally(Helpers.toFileUrl(iFuse.state.mountPath))
            }
        }
    }
}
