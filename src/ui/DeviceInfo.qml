import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 

Item {
    id : root
    required property var info
    required property var device

    function v(key, fallback) {
        if (!info) return fallback
        const val = info[key]
        if (val === undefined || val === null || val === "") return fallback
        return val
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 20

        RowLayout {
            spacing: 12

            ColumnLayout {
                DeviceImage { 
                    iosVersion: info ? info.ios_version_major : 0
                    displayName: v("product_type", "Unknown Device")
                }
                RowLayout {
                    //center
                    anchors.horizontalCenter: parent.horizontalCenter
                    // implicitHeight: 50
                    spacing: 10
                    // 
                    Button {
                        icon.source: "qrc:/resources/icons/ic_outline-power-settings-new.svg"
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        //FIXME: wire up
                        onClicked: {
                        }
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                    Button {
                        icon.source: "qrc:/resources/icons/ic_twotone-restart-alt.svg"
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        //FIXME: wire up
                        onClicked: {
                        }
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                    Button {
                        icon.source: "qrc:/resources/icons/hugeicons_wrench-01.svg"
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        //FIXME: wire up
                        onClicked: {
                        }
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                }
            }

            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Label {
                        text: v("product_type", "TODO")
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
                
                Item {
                    Layout.fillWidth: true
                    implicitHeight: grid.implicitHeight + 20  // match your margins
                    // implicitHeight: grid.implicitHeight

                    Rectangle {
                        anchors.fill: parent
                        
                        color: Qt.rgba(255, 255, 255, 0.1)
                        radius: 4
                        z: -1
                    }
                
                    GridLayout {
                        id: grid
                        columns: 4
                        columnSpacing: 14
                        rowSpacing: 8
                        anchors.fill: parent
                        anchors.margins: 10

                        // Row 0
                        Label { text: "iOS Version:"; font.bold: true }
                        Label { text: v("ProductVersion", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Device Name:"; font.bold: true }
                        Label { text: v("DeviceName", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 1
                        Label { text: "Activation State:"; font.bold: true }
                        Label { text: v("ActivationState", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Device Class:"; font.bold: true }
                        Label { text: v("DeviceClass", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 2
                        Label { text: "Jailbroken:"; font.bold: true }
                        Label { text: v("Jailbroken", "TODO") ? "Yes" : "No"; elide: Text.ElideRight; Layout.fillWidth: true }
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
                        Label { text: v("region", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

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
                        Label { text: v("SerialNumber", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 9
                        Label { text: "IMEI:"; font.bold: true }
                        Label { text: v("InternationalMobileEquipmentIdentity", "TODO"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "UDID:"; font.bold: true }
                        Label { text: v("UniqueDeviceID", "TODO"); elide: Text.ElideMiddle; Layout.fillWidth: true }
                    }
                }
            }
        }

        DiskUsage {
            Layout.fillWidth: true
            device : root.device
        }
    }
}