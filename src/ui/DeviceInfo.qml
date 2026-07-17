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

    function activationStateColor(state) {
        if (state === "Activated" || state === "WildcardActivated")
            return Theme.systemGreen
        if (state === "FactoryActivated")
            return Theme.systemOrange
        return Theme.systemRed
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
                    id: deviceActions
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    IconToolButton {
                        id: shutdownButton
                        icon.source: "qrc:/resources/icons/ic_outline-power-settings-new.svg"
                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        ToolTip.text: qsTr("Shut down device")
                        onClicked: Toolbox.toolClicked(11, true)
                    }
                    IconToolButton {
                        id: restartButton
                        icon.source: "qrc:/resources/icons/ic_twotone-restart-alt.svg"
                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        ToolTip.text: qsTr("Restart device")
                        onClicked: Toolbox.toolClicked(10, true)
                    }
                    IconToolButton {
                        id: recoveryButton
                        icon.source: "qrc:/resources/icons/hugeicons_wrench-01.svg"
                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        ToolTip.text: qsTr("Enter recovery mode")
                        onClicked: Toolbox.toolClicked(12, true)
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

                        CopyableText {
                            text: v("product_type", qsTr("Unknown Device"))
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        CopyableText {
                            horizontalPadding: 4
                            verticalPadding: 4
                            backgroundColor: Theme.accent
                            backgroundRadius: 13
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

                            color: palette.window
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            spacing: 3.5

                            CopyableText {
                                text: info.DIAG_INFO.current_battery_level + "%"
                                color: palette.text
                                visible: info.DIAG_INFO.is_charging
                            }

                            BatteryIndicator {
                                value: info.DIAG_INFO.current_battery_level
                                isCharging: info.DIAG_INFO.is_charging
                            }
                        }

                        CopyableText {
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
                        CopyableText { text: v("ProductVersion", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Device Name:"; font.bold: true }
                        CopyableText { text: v("DeviceName", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 1
                        Label { text: "Activation State:"; font.bold: true }
                        CopyableText {
                            text: v("ActivationState", qsTr("Unknown"))
                            color: root.activationStateColor(text)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label { text: "Device Class:"; font.bold: true }
                        CopyableText { text: v("DeviceClass", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 2
                        Label { text: "Jailbroken:"; font.bold: true }
                        CopyableText { text: v("Jailbroken", false) ? qsTr("Yes") : qsTr("No"); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Model Number:"; font.bold: true }
                        CopyableText { text: v("ModelNumber", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 3
                        Label { text: "CPU Architecture:"; font.bold: true }
                        CopyableText { text: v("CPUArchitecture", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Build Version:"; font.bold: true }
                        CopyableText { text: v("BuildVersion", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 4
                        Label { text: "Hardware Model:"; font.bold: true }
                        CopyableText { text: v("HardwareModel", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Region:"; font.bold: true }
                        CopyableText { text: v("region", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 5
                        Label { text: "Hardware Platform:"; font.bold: true }
                        CopyableText { text: v("HardwarePlatform", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Firmware Version:"; font.bold: true }
                        CopyableText { text: v("FirmwareVersion", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 6
                        Label { text: "Bluetooth Address:"; font.bold: true }
                        PrivateText { text: v("BluetoothAddress", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Wi‑Fi Address:"; font.bold: true }
                        PrivateText { text: v("WiFiAddress", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }

                        // Row 7
                        Label { text: "Ethernet Address:"; font.bold: true }
                        PrivateText { text: v("EthernetAddress", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: "Battery Health:"; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            CopyableText {
                                text: root.info.DIAG_INFO.battery_health
                                elide: Text.ElideRight
                            }

                            Button {
                                text: qsTr("More")
                                onClicked: {
                                    // TODO: Implement the battery health details UI.
                                }
                            }
                        }

                        // Row 8
                        Label { text: "Production Device:"; font.bold: true }
                        CopyableText { text: v("ProductionDevice", qsTr("Unknown")); elide: Text.ElideRight; Layout.fillWidth: true }
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
