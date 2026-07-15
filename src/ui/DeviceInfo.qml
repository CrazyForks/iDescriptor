import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts
import "./base"

Item {
    id : root
    required property var info
    required property var device
    readonly property int contentMargin: 20
    readonly property int contentMaxWidth: 1040
    readonly property real diskUsageWidthRatio: 0.8

    function v(key, fallback) {
        if (!info) return fallback
        const val = info[key]
        if (val === undefined || val === null || val === "") return fallback
        return val
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(root.contentMargin, (parent.height - implicitHeight) / 2)
        width: Math.min(Math.max(0, parent.width - root.contentMargin * 2), root.contentMaxWidth)
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            ColumnLayout {
                DeviceImage { 
                    iosVersion: info ? info.ios_version_major : 0
                    displayName: v("product_type", "Unknown Device")
                }
                RowLayout {
                    //center
                    // anchors.horizontalCenter: parent.horizontalCenter
                    Layout.alignment: Qt.AlignHCenter
                    // implicitHeight: 50
                    spacing: 10
                    // 
                    Button {
                        icon.source: "qrc:/resources/icons/ic_outline-power-settings-new.svg"
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        onClicked: Toolbox.toolClicked(10, true)
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                    Button {
                        icon.source: "qrc:/resources/icons/ic_twotone-restart-alt.svg"
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        onClicked: Toolbox.toolClicked(11, true)
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                    Button {
                        icon.source: "qrc:/resources/icons/hugeicons_wrench-01.svg"
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        onClicked: Toolbox.toolClicked(12, true)
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                }
            }

            ColumnLayout {
                id: detailsColumn
                spacing: 20
                Layout.fillWidth: true

                SectionBox {
                    Layout.fillWidth: true
                    padding:6

                    RowLayout {
                        spacing: 15

                        Label {
                            text: v("product_type", qsTr("Unknown Device"))
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Label {
                            padding: 4
                            text: {
                                const totalDiskCapacity = v("TotalDiskCapacity", null)
                                if (totalDiskCapacity === null) return ""
                                const gb = totalDiskCapacity / (1000 * 1000 * 1000)
                                if (gb >= 1000) {
                                    const tb = gb / 1024
                                    return tb.toFixed(1) + " TB"
                                } else {
                                    return gb.toFixed(0) + " GB"
                                }
                            }

                            background: Rectangle {
                                color: Theme.accent
                                radius: 13
                            }
                            color: palette.text
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            text: info.DIAG_INFO.is_charging ? qsTr("Charging") : info.is_wireless ? qsTr("Wireless") : qsTr("Not Charging")
                            color: info.DIAG_INFO.is_charging ? Theme.green : palette.text
                        }

                        BatteryIndicator {
                            value: info.DIAG_INFO.current_battery_level
                            isCharging: info.DIAG_INFO.is_charging
                        }

                        Label {
                            // FIXME: hardcoded 
                            text: "5W/USB"
                            color: palette.text
                        }
                    }
                }
                
                Item {
                    Layout.fillWidth: true
                    implicitHeight: grid.implicitHeight + 20
                    // implicitHeight: grid.implicitHeight

                    SectionBox {
                        anchors.fill: parent
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
                        Label { text: v("ProductVersion", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Device Name:"; font.bold: true }
                        Label { text: v("DeviceName", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 1
                        Label { text: "Activation State:"; font.bold: true }
                        Label { text: v("ActivationState", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Device Class:"; font.bold: true }
                        Label { text: v("DeviceClass", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 2
                        Label { text: "Jailbroken:"; font.bold: true }
                        Label { text: v("Jailbroken", "No") ? "Yes" : "No"; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Model Number:"; font.bold: true }
                        Label { text: v("ModelNumber", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 3
                        Label { text: "CPU Architecture:"; font.bold: true }
                        Label { text: v("CPUArchitecture", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Build Version:"; font.bold: true }
                        Label { text: v("BuildVersion", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 4
                        Label { text: "Hardware Model:"; font.bold: true }
                        Label { text: v("HardwareModel", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Region:"; font.bold: true }
                        Label { text: v("region", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 5
                        Label { text: "Hardware Platform:"; font.bold: true }
                        Label { text: v("HardwarePlatform", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Firmware Version:"; font.bold: true }
                        Label { text: v("FirmwareVersion", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 6
                        Label { text: "Bluetooth Address:"; font.bold: true }
                        PrivateText { text: v("BluetoothAddress", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Wi‑Fi Address:"; font.bold: true }
                        PrivateText { text: v("WiFiAddress", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 7
                        Label { text: "Ethernet Address:"; font.bold: true }
                        PrivateText { text: v("EthernetAddress", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Battery Health:"; font.bold: true }
                        Label { text: root.info.DIAG_INFO.battery_health; elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 8
                        Label { text: "Production Device:"; font.bold: true }
                        Label { text: v("ProductionDevice", "Unknown"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Serial Number:"; font.bold: true }
                        PrivateText { text: v("SerialNumber", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 9
                        Label { text: "IMEI:"; font.bold: true }
                        PrivateText { text: v("InternationalMobileEquipmentIdentity", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "UDID:"; font.bold: true }
                        PrivateText { text: v("UniqueDeviceID", qsTr("Unknown")); Layout.fillWidth: true }
                    }
                }
                
                DiskUsage {
                    Layout.preferredWidth: detailsColumn.width * root.diskUsageWidthRatio
                    Layout.alignment: Qt.AlignHCenter
                    device : root.device
                }
            }
        }

    }
}
