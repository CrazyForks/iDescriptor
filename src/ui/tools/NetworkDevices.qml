import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../base"
import "../+windows"

ToolWindow {
    id: root
    width: 500
    height: 500
    minimumWidth: 300
    minimumHeight: 300
    maximumWidth: 500
    maximumHeight: 500
    title: qsTr("Network Devices - iDescriptor")
    auto_close: false

    // device fields expected from NetworkDevice::toVariantMap():
    // name, address, port, macAddress (may or may not be present)
    ListModel { id: deviceModel }

    property string statusText: qsTr("Scanning for network devices...")

    function normalizeDevice(mac, dev) {
        return {
            mac: mac || dev.macAddress || "",
            name: dev.name || dev.deviceName || qsTr("Unknown device"),
            address: dev.address || dev.ip || "",
            port: dev.port || "",
            raw: dev
        }
    }

    function indexByMac(mac) {
        for (let i = 0; i < deviceModel.count; ++i) {
            if (deviceModel.get(i).mac === mac)
                return i
        }
        return -1
    }

    function indexByName(name) {
        for (let i = 0; i < deviceModel.count; ++i) {
            if (deviceModel.get(i).name === name)
                return i
        }
        return -1
    }

    function updateStatusLabel() {
        if (deviceModel.count === 0)
            statusText = qsTr("No network devices found")
        else
            statusText = qsTr("Found %1 network device(s)").arg(deviceModel.count)
    }

    function refreshDevices() {
        deviceModel.clear()

        // NetworkDeviceProvider.getNetworkDevices(): QMap<QString, QVariant>
        const map = NetworkDeviceProvider.getNetworkDevices()
        if (!map) {
            updateStatusLabel()
            return
        }

        const keys = Object.keys(map)
        for (let k = 0; k < keys.length; ++k) {
            const mac = keys[k]
            const dev = map[mac]
            deviceModel.append(normalizeDevice(mac, dev))
        }

        updateStatusLabel()
        stateView.viewState = StateView.State.Content
    }

    Component.onCompleted: refreshDevices()

    Connections {
        target: NetworkDeviceProvider

        function onDeviceAdded(device) {
            const mac = device.macAddress || device.mac || ""
            if (mac && root.indexByMac(mac) >= 0)
                return

            deviceModel.append(root.normalizeDevice(mac, device))
            root.updateStatusLabel()
            stateView.viewState = StateView.State.Content
        }

        function onDeviceRemoved(deviceName) {
            let i = root.indexByMac(deviceName)
            if (i < 0)
                i = root.indexByName(deviceName)
            if (i >= 0)
                deviceModel.remove(i, 1)
            root.updateStatusLabel()
        }
    }

    StateView {
        id: stateView
        anchors.fill: parent
        viewState: StateView.State.Loading

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            // Status label
            Label {
                Layout.fillWidth: true
                text: root.statusText
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 12
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }

            Pane {
                background: Rectangle {
                    color: "transparent"
                }
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 10

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: qsTr("Network Devices")
                        font.pointSize: 14
                        font.weight: Font.Bold
                    }

                    // Scroll area
                    ScrollView {
                        id: deviceScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        // Scroll content
                        Column {
                            width: deviceScroll.availableWidth
                            spacing: 8

                            Repeater {
                                model: deviceModel

                                delegate: SectionBox {
                                    width: parent.width
                                    implicitHeight: content.implicitHeight + 24
                                    height: implicitHeight

                                    ColumnLayout {
                                        id: content
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        // Device name (primary)
                                        Label {
                                            Layout.fillWidth: true
                                            text: model.name
                                            wrapMode: Text.WordWrap
                                            font.pointSize: 13
                                            font.weight: Font.Medium
                                        }

                                        // Device info container
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            // Address info
                                            Label {
                                                text: qsTr("IP: %1").arg(model.address || "-")
                                                font.pointSize: 11
                                                opacity: 0.8
                                            }

                                            // Port info
                                            Label {
                                                text: qsTr("Port: %1").arg(model.port !== "" ? model.port : "-")
                                                font.pointSize: 11
                                                opacity: 0.8
                                            }

                                            Item { Layout.fillWidth: true }

                                            Label {
                                                text: "●"
                                                font.pointSize: 14
                                                color: Qt.platform.os === "windows" ? "#0078d4" : "#2e7d32"
                                            }
                                        }
                                    }
                                }
                            }

                            Item { width: 1; height: 1 }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
