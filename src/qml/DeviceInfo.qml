import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    property var info: ({})
    // property string udid: ""

    function v(key, fallback) {
        if (!info) return fallback
        const val = info[key]
        if (val === undefined || val === null || val === "") return fallback
        return val
    }

    RowLayout {
        spacing: 12

        DeviceImage { }

        ColumnLayout {
            spacing: 10
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: v("DeviceClass", "TODO")
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    // FIXME: hardcoded 
                    text: "5W/USB"
                    color: "#666"
                }
            }

            GridLayout {
                id: grid
                columns: 4
                columnSpacing: 14
                rowSpacing: 8
                Layout.fillWidth: true

                // Row 0
                Label { text: "iOS Version:"; font.bold: true }
                Label { text: v("ProductVersion", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Device Name:"; font.bold: true }
                Label { text: v("DeviceName", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 1
                Label { text: "Activation State:"; font.bold: true }
                Label { text: "TODO"; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Device Class:"; font.bold: true }
                Label { text: v("DeviceClass", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 2
                Label { text: "Jailbroken:"; font.bold: true }
                Label { text: "TODO"; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Model Number:"; font.bold: true }
                Label { text: v("ModelNumber", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 3
                Label { text: "CPU Architecture:"; font.bold: true }
                Label { text: v("CPUArchitecture", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Build Version:"; font.bold: true }
                Label { text: v("BuildVersion", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 4
                Label { text: "Hardware Model:"; font.bold: true }
                Label { text: v("HardwareModel", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Region:"; font.bold: true }
                Label { text: "TODO"; elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 5
                Label { text: "Hardware Platform:"; font.bold: true }
                Label { text: v("HardwarePlatform", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Firmware Version:"; font.bold: true }
                Label { text: v("FirmwareVersion", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 6
                Label { text: "Bluetooth Address:"; font.bold: true }
                Label { text: v("BluetoothAddress", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Wi‑Fi Address:"; font.bold: true }
                Label { text: v("WiFiAddress", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 7
                Label { text: "Ethernet Address:"; font.bold: true }
                Label { text: v("EthernetAddress", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Battery Health:"; font.bold: true }
                Label { text: "TODO"; elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 8
                Label { text: "Production Device:"; font.bold: true }
                Label { text: "TODO"; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Serial Number:"; font.bold: true }
                Label { text: "TODO"; elide: Text.ElideRight; Layout.fillWidth: true }

                // Row 9
                Label { text: "IMEI:"; font.bold: true }
                Label { text: "TODO"; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "UDID:"; font.bold: true }
                Label { text: v("UniqueDeviceID", "TODO"); elide: Text.ElideMiddle; Layout.fillWidth: true }
            }
        }
    }
}