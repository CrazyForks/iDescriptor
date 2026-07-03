import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "." as App
import "./base"

Item {
    id: root

    property var networkDeviceCards : ({})
    ListModel { id: deviceModel }

    property string statusText: qsTr("Scanning for network devices...")

    function normalizeDevice(mac, dev) {
        return {
            mac: mac || dev.macAddress || "",
            name: dev.name || dev.deviceName || qsTr("Unknown device"),
            address: dev.address || dev.ip || "",
            port: dev.port || "",
            raw: dev,

            // UI state
            state: "idle",           // idle|connecting|failed|noPairing|connected|alreadyExists
            stateText: "",
            buttonText: qsTr("Connect"),
            buttonEnabled: true
        }
    }

    function indexByMac(mac) {
        for (var i = 0; i < deviceModel.count; i++) {
            if (deviceModel.get(i).mac === mac) return i
        }
        return -1
    }

    function indexByIp(ip) {
        for (var i = 0; i < deviceModel.count; i++) {
            if (deviceModel.get(i).address === ip) return i
        }
        return -1
    }

    function setStatusAtIndex(i, state) {
        if (state === "failed") {
            deviceModel.setProperty(i, "state", "failed")
            deviceModel.setProperty(i, "buttonText", qsTr("Failed to connect"))
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "noPairing") {
            deviceModel.setProperty(i, "state", "noPairing")
            deviceModel.setProperty(i, "buttonText", qsTr("No pairing file"))
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "connecting") {
            deviceModel.setProperty(i, "state", "connecting")
            deviceModel.setProperty(i, "buttonText", qsTr("Connecting..."))
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "connected") {
            deviceModel.setProperty(i, "state", "connected")
            deviceModel.setProperty(i, "buttonText", qsTr("Connected"))
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "alreadyExists") {
            deviceModel.setProperty(i, "state", "alreadyExists")
            deviceModel.setProperty(i, "buttonText", qsTr("Already connected"))
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else {
            deviceModel.setProperty(i, "state", "idle")
            deviceModel.setProperty(i, "buttonText", qsTr("Connect"))
            deviceModel.setProperty(i, "buttonEnabled", true)
        }
    }

    function setStatusForMac(mac, state) {
        var i = indexByMac(mac)
        if (i < 0) {
            console.log("setStatusForMac: No device found with MAC:", mac)
            return false
        }

        setStatusAtIndex(i, state)
        return true
    }

    function setStatusForIp(ip, state) {
        var i = indexByIp(ip)
        if (i < 0) return false

        setStatusAtIndex(i, state)
        return true
    }

    function updateStatusLabel() {
        if (deviceModel.count === 0) statusText = qsTr("No network devices found")
        else statusText = qsTr("Found %1 network device(s)").arg(deviceModel.count)
    }

    function refreshDevices() {
        deviceModel.clear()

        // NetworkDeviceProvider.getNetworkDevices(): QMap<QString, QVariant>
        var map = NetworkDeviceProvider.getNetworkDevices()
        if (!map) {
            statusText = qsTr("No network devices found")
            return
        }

        var keys = Object.keys(map)
        for (var k = 0; k < keys.length; k++) {
            var mac = keys[k]
            var dev = map[mac]
            deviceModel.append(normalizeDevice(mac, dev))
        }
        updateStatusLabel()
    }

    Component.onCompleted: refreshDevices()

    Connections {
        target: NetworkDeviceProvider

        function onDeviceAdded(device) {
            var mac = device.macAddress || device.mac || ""
            if (!mac) return

            var i = root.indexByMac(mac)
            if (i >= 0) return

            deviceModel.append(root.normalizeDevice(mac, device))
            root.updateStatusLabel()
        }

        function onDeviceRemoved(macAddress) {
            var i = root.indexByMac(macAddress)
            if (i >= 0) deviceModel.remove(i, 1)
            root.updateStatusLabel()
        }
    }

    // Backend events (core)
    Connections {
        target: core

        function onInitFailed(macAddress) {
            root.setStatusForMac(macAddress, "failed")
        }

        function onNoPairingFile(macAddress) {
            root.setStatusForMac(macAddress, "noPairing")
        }

        function onCustomInitFailed(ip, macAddress, error) {
            console.log("Custom network device initialization failed:", ip, macAddress, error)
            if (!macAddress || !root.setStatusForMac(macAddress, "failed")) {
                root.setStatusForIp(ip, "failed")
            }
        }
    }

    Connections {
        target: App.DeviceContext

        function onInitStarted(mac) {
            root.setStatusForMac(mac, "connecting")
        }

        function onDeviceAdded(mac) {
            root.setStatusForMac(mac, "connected")
        }
        function onDeviceAlreadyExistsMAC(mac) {
            console.log("Device with MAC:", mac, "already exists. Setting status to 'alreadyExists'");
            root.setStatusForMac(mac, "alreadyExists")
        }
    }

    //eval interval, every 30 seconds
    Timer {
        id: evalTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            //FIXME
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Label {
            Layout.fillWidth: true
            text: root.statusText
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 12
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
        }

        SectionBox {
            Layout.fillWidth: true
            Layout.fillHeight: true

            //FIXMEl: need a better way to limit the size
            Layout.maximumHeight: 400
            Layout.maximumWidth: 600

            ColumnLayout {
                spacing: 8

                Label {
                    text: qsTr("Network Devices")
                    font.pointSize: 14
                    font.weight: Font.Bold
                }

                ScrollView {
                    id: deviceScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Column {
                        width: deviceScroll.availableWidth
                        spacing: 8

                        Repeater {
                            model: deviceModel

                            delegate: SectionBox {
                                id: deviceSectionBox
                                width: parent.width
                                height: implicitHeight

                                ColumnLayout {
                                    id: content
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Label {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 44
                                        text: name
                                        wrapMode: Text.WordWrap
                                        font.pointSize: 13
                                        font.weight: Font.Medium
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Label {
                                            text: qsTr("IP: %1").arg(address || "-")
                                            font.pointSize: 11
                                            opacity: 0.8
                                        }

                                        Label {
                                            text: qsTr("Port: %1").arg(port !== "" ? port : "-")
                                            font.pointSize: 11
                                            opacity: 0.8
                                        }

                                        Item { Layout.fillWidth: true }

                                        Button {
                                            text: buttonText
                                            enabled: buttonEnabled
                                            onClicked: {
                                                buttonText = qsTr("Connecting...")
                                                App.DeviceContext.tryToConnectToNetworkDevice(mac, address, true, true)
                                                resetTimer.stop()
                                                resetTimer.interval = 10000
                                                resetTimer.start()
                                            }
                                        }

                                        Label {
                                            text: "●"
                                            font.pointSize: 14
                                            color: {
                                                switch (state) {
                                                case "failed": return "#d83b01"
                                                case "noPairing": return "#ffb900"
                                                case "connecting": return "#0078d4"
                                                case "connected": return "#2e7d32"
                                                case "alreadyExists": return "#6b6b6b"
                                                default: return "#2e7d32"
                                                }
                                            }
                                        }
                                    }

                                }

                                overlay: [
                                    ToolButton {
                                        id: sectionMenuButton
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: 1
                                        anchors.rightMargin: 1
                                        enabled: !!address
                                        icon.source: "qrc:/resources/icons/mi_options-vertical.svg"
                                        icon.color: palette.text
                                        onClicked: sectionMenu.open()
                                        background : Rectangle {
                                            color : "transparent"
                                        }


                                        Menu {
                                            id: sectionMenu

                                            MenuItem {
                                                text: qsTr("Connect via custom pairing file")
                                                onTriggered: pairingFileDialog.open()
                                            }
                                        }
                                    }
                                ]

                                FileDialog {
                                    id: pairingFileDialog
                                    title: qsTr("Choose pairing file")
                                    fileMode: FileDialog.OpenFile
                                    onAccepted: {
                                        var path = QmlUtils.url_to_path(selectedFile)
                                        if (!path || !address) return

                                        App.DeviceContext.tryToConnectToNetworkDeviceCustom(address, path)
                                        root.setStatusForIp(address, "connecting")
                                        Helpers.setTimeout(function() {
                                            root.setStatusForIp(address, "idle")
                                        }, 10000)
                                    }
                                }
                            }
                        }

                        Item { width: 1; height: 1 } // spacer
                    }
                }
            }
        }
    }
}
