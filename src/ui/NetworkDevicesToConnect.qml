import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    // device fields expected from NetworkDevice::toVariantMap():
    // name, address, port, macAddress (may or may not be present)
    ListModel { id: deviceModel }

    property string statusText: "Scanning for network devices..."

    function _normalizeDevice(mac, dev) {
        return {
            mac: mac || dev.macAddress || "",
            name: dev.name || dev.deviceName || "Unknown device",
            address: dev.address || dev.ip || "",
            port: dev.port || "",
            raw: dev,

            // UI state
            state: "idle",           // idle|connecting|failed|no_pairing|connected|already_exists
            stateText: "",
            buttonText: "Connect",
            buttonEnabled: true
        }
    }

    function _indexByMac(mac) {
        for (var i = 0; i < deviceModel.count; i++) {
            if (deviceModel.get(i).mac === mac) return i
        }
        return -1
    }

    function _setStatusForMac(mac, state) {
        var i = _indexByMac(mac)
        if (i < 0) return

        if (state === "failed") {
            deviceModel.setProperty(i, "state", "failed")
            deviceModel.setProperty(i, "buttonText", "Failed to connect")
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "no_pairing") {
            deviceModel.setProperty(i, "state", "no_pairing")
            deviceModel.setProperty(i, "buttonText", "No pairing file")
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "connecting") {
            deviceModel.setProperty(i, "state", "connecting")
            deviceModel.setProperty(i, "buttonText", "Connecting...")
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "connected") {
            deviceModel.setProperty(i, "state", "connected")
            deviceModel.setProperty(i, "buttonText", "Connected")
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else if (state === "already_exists") {
            deviceModel.setProperty(i, "state", "already_exists")
            deviceModel.setProperty(i, "buttonText", "Already connected")
            deviceModel.setProperty(i, "buttonEnabled", false)
        } else {
            deviceModel.setProperty(i, "state", "idle")
            deviceModel.setProperty(i, "buttonText", "Connect")
            deviceModel.setProperty(i, "buttonEnabled", true)
        }
    }

    function _updateStatusLabel() {
        if (deviceModel.count === 0) statusText = "No network devices found"
        else statusText = "Found " + deviceModel.count + " network device(s)"
    }

    function refreshDevices() {
        deviceModel.clear()

        // NetworkDeviceProvider.getNetworkDevices(): QMap<QString, QVariant>
        var map = NetworkDeviceProvider.getNetworkDevices()
        if (!map) {
            statusText = "No network devices found"
            return
        }

        var keys = Object.keys(map)
        for (var k = 0; k < keys.length; k++) {
            var mac = keys[k]
            var dev = map[mac]
            deviceModel.append(_normalizeDevice(mac, dev))
        }
        _updateStatusLabel()
    }

    Component.onCompleted: refreshDevices()

    // Live updates from C++ provider
    Connections {
        target: NetworkDeviceProvider

        function onDeviceAdded(device) {
            var mac = device.macAddress || device.mac || ""
            if (!mac) return

            var i = root._indexByMac(mac)
            if (i >= 0) return

            deviceModel.append(root._normalizeDevice(mac, device))
            root._updateStatusLabel()
        }

        function onDeviceRemoved(macAddress) {
            var i = root._indexByMac(macAddress)
            if (i >= 0) deviceModel.remove(i, 1)
            root._updateStatusLabel()
        }
    }

    // Backend events (core)
    Connections {
        target: core

        function onInit_failed(mac_address) {
            root._setStatusForMac(mac_address, "failed")
        }

        function onNo_pairing_file(mac_address) {
            root._setStatusForMac(mac_address, "no_pairing")
        }

        // FIXME: implement and wire these events on core (parity with QWidget/AppContext):
        // - initStarted(mac)        -> setStatusForMac(mac, "connecting")
        // - deviceAdded(mac)        -> setStatusForMac(mac, "connected")
        // - deviceAlreadyExistsMAC  -> setStatusForMac(mac, "already_exists")
    }

    // eval interval (every 30 seconds)
    Timer {
        id: evalTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            // FIXME: implement auto-connect eval logic + settings gate (like SettingsManager::autoConnectWirelessDevices()).
            // FIXME: implement events on core to reflect initStarted/connected/already exists.
            // For now: placeholder to keep behavior parity (timer exists).
            // console.log("eval tick: devices=", deviceModel.count)
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

        Pane {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 10

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Label {
                    text: "Network Devices"
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

                            delegate: Rectangle {
                                width: parent.width
                                implicitHeight: content.implicitHeight + 24
                                height: implicitHeight
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.color: Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1

                                Timer {
                                    id: resetTimer
                                    repeat: false
                                    onTriggered: root._setStatusForMac(mac, "idle")
                                }

                                ColumnLayout {
                                    id: content
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6

                                    Label {
                                        Layout.fillWidth: true
                                        text: name
                                        wrapMode: Text.WordWrap
                                        font.pointSize: 13
                                        font.weight: Font.Medium
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Label {
                                            text: "IP: " + (address || "—")
                                            font.pointSize: 11
                                            opacity: 0.8
                                        }

                                        Label {
                                            text: "Port: " + (port !== "" ? port : "—")
                                            font.pointSize: 11
                                            opacity: 0.8
                                        }

                                        Item { Layout.fillWidth: true }

                                        Button {
                                            text: buttonText
                                            enabled: buttonEnabled
                                            onClicked: {
                                                root._setStatusForMac(mac, "connecting")
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
                                                case "no_pairing": return "#ffb900"
                                                case "connecting": return "#0078d4"
                                                case "connected": return "#2e7d32"
                                                case "already_exists": return "#6b6b6b"
                                                default: return "#2e7d32"
                                                }
                                            }
                                        }
                                    }

                                    // State-driven auto-reset timings (mirrors QWidget roughly)
                                    Connections {
                                        target: deviceModel
                                        function onDataChanged() {
                                            // ...existing code...
                                        }
                                    }

                                    Component.onCompleted: {
                                        // no-op
                                    }

                                    onStateChanged: {
                                        // ...existing code...
                                    }

                                    // react to model.state changes
                                    Binding { target: resetTimer; property: "running"; value: false }

                                    // Start/reset timer when entering transient states
                                    // (failed: 2s, no_pairing: 5s, connected: 10s, already_exists: 3s)
                                    // NOTE: we use Component.onCompleted + onModelChanged pattern via onButtonTextChanged below.
                                    // onButtonTextChanged: {
                                    //     resetTimer.stop()
                                    //     if (model.state === "failed") { resetTimer.interval = 2000; resetTimer.start() }
                                    //     else if (model.state === "no_pairing") { resetTimer.interval = 5000; resetTimer.start() }
                                    //     else if (model.state === "connected") { resetTimer.interval = 10000; resetTimer.start() }
                                    //     else if (model.state === "already_exists") { resetTimer.interval = 3000; resetTimer.start() }
                                    // }
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