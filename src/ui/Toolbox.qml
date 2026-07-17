pragma Singleton

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Dialogs
import "." as App
import "./base"

Item {
    id: root
    anchors.fill: parent

    MessageDialog {
        id: errorDialog
        title: qsTr("Error")
        text: ""
    }

    MessageDialog {
        id: infoDialog
        title: qsTr("Information")
        text: ""
    }

    AnimatedDialog {
        id: confirmActionDialog
        modal: true
        focus: true
        anchors.centerIn: parent
        title: ""
        standardButtons: Dialog.Yes | Dialog.No

        property string action: ""
        property string message: ""

        Label {
            text: confirmActionDialog.message
            wrapMode: Text.WordWrap
            width: Math.min(root.width - 64, 420)
        }

        onAccepted: root.performDeviceAction(action)
    }

    property string currentDeviceUdid: ""
    property var airplayInstance: null
    property var devDiskImagesInstance: null
    property var wirelessGalleryImportInstance: null
    property var ifuseInstance: null
    property var networkDevicesInstance: null
    property var backupManagerInstance: null
    readonly property bool hasDevice: App.DeviceContext.devices && App.DeviceContext.devices.count > 0

    function showError(message) {
        errorDialog.text = message
        errorDialog.open()
    }

    function showInfo(message) {
        infoDialog.text = message
        infoDialog.open()
    }

    function confirmDeviceAction(action, title, message) {
        confirmActionDialog.action = action
        confirmActionDialog.title = title
        confirmActionDialog.message = message
        confirmActionDialog.open()
    }

    function performDeviceAction(action) {
        const device = App.DeviceContext.getDevice(currentDeviceUdid)

        let success = false
        switch (action) {
            case "restart":
                success = device.service_manager.restart()
                break
            case "shutdown":
                success = device.service_manager.shutdown()
                break
            case "recovery":
                success = device.service_manager.enter_recovery_mode()
                break
            default:
                showError(qsTr("Unknown device action."))
                return
        }

        if (!success)
            showError(qsTr("Failed to send the command to the device. Make sure it is connected and unlocked."))
        else
            showInfo(qsTr("Action '%1' sent successfully.").arg(action))
    }

    function createComp(loc, args = {}) {
        const comp = Qt.createComponent(loc)
        if (comp.status === Component.Ready) {
            const win = comp.createObject(root,args)
            if (win !== null) {
                win.show()
                return win
            } else {
                console.error("createObject failed:", comp.errorString())
            }

        } else if (comp.status === Component.Error) {
            console.error("Component failed to load:", comp.errorString())
        }

        return null
    }

    function focusToolWindow(win) {
        if (!win)
            return false

        win.show()
        win.raise()
        win.requestActivate()
        return true
    }


    // 0 Airplayer, 1 SimulateLocation, 2 LiveScreen, 3 QueryMobileGestalt, 4 DeveloperDiskImages,
    // 5 WirelessGalleryImport, 6 iFuse, 7 CableInfo, 8 NetworkDevices, 9 MountDevImage,
    // 10 Restart, 11 Shutdown, 12 RecoveryMode, 13 EnableWifiConnections, 14 BackupManager,
    // 15 TransferSpeedTest
    // signal toolClicked(int toolId, bool requiresDevice)
    function toolClicked(toolId, requiresDevice) {
        const device = App.DeviceContext.getDevice(currentDeviceUdid)

        if (requiresDevice) {
            if (!device) {
                console.log("DEVICE DISAPPERED")
                return
            }
        }

        const createCompWrapped = (loc, _args) => {
            const args = {
                device,
                udid: currentDeviceUdid
            }
            Object.assign(args, _args || {})
            return createComp(loc, args)
        }

        function createSingletonComp(loc, instanceName, _args = {}) {
            if (focusToolWindow(root[instanceName])) return

            const args = {
                device,
                udid: currentDeviceUdid,
                auto_close : false
            }

            Object.assign(args, _args || {})

            const win = createComp(loc, args)
            if (!win)
                return

            root[instanceName] = win
            win.closing.connect(function(closeEvent) {
                if (!closeEvent.accepted)
                    return

                if (root[instanceName] === win)
                    root[instanceName] = null
                win.destroy(0)
            })
        }

        switch (toolId) {
            case 0:
                // if (focusToolWindow(airplayInstance))
                    // return

                const gl_plugin_loaded = AirplayImp.load_gst_gl()
                if (!gl_plugin_loaded) {
                    switch (Qt.platform.os) {
                        case "linux":
                            errorDialog.text = qsTr("Failed to load gst gl plugin, make sure you have QT_QPA_PLATFORM=xcb env var set")
                            break;
                        case "windows":
                            errorDialog.text = qsTr("Failed to load gst gl plugin, make sure you can use OpenGL")
                            break;
                        case "macos":
                            errorDialog.text = qsTr("Failed to load gst gl plugin, make sure you can use OpenGL")
                            break;
                        default:
                            errorDialog.text = qsTr("Failed to load gst gl plugin")

                    }
                    errorDialog.open()
                    return;
                }

                createSingletonComp("./tools/Airplay.qml", "airplayInstance")
                break;
            case 1:
                createCompWrapped("./tools/SimulateLocation.qml")
                break;
            case 2:
                createCompWrapped("./tools/LiveScreen.qml")
                break;
            case 3:
                // FIXME: doesnt work iOS 17 and above
                createCompWrapped("./tools/QueryMobileGestalt.qml")
                break;
            case 4:
                createSingletonComp("./tools/DevDiskImages.qml", "devDiskImagesInstance")
                break;
            case 5:
                createSingletonComp("./tools/WirelessGalleryImport.qml", "wirelessGalleryImportInstance")
                break;
            case 6:
                createSingletonComp("./tools/IFuse.qml", "ifuseInstance")
                break;
            case 7:
                createCompWrapped("./tools/CableInfo.qml")
                break;
            case 8:
                createSingletonComp("./tools/NetworkDevices.qml", "networkDevicesInstance")
                break;
            case 10:
                confirmDeviceAction(
                    "restart",
                    qsTr("Restart Device"),
                    qsTr("Are you sure you want to restart this device?")
                )
                break;
            case 11:
                confirmDeviceAction(
                    "shutdown",
                    qsTr("Shut Down Device"),
                    qsTr("Are you sure you want to shut down this device?")
                )
                break;
            case 12:
                confirmDeviceAction(
                    "recovery",
                    qsTr("Enter Recovery Mode"),
                    qsTr("Are you sure you want to put this device into recovery mode?")
                )
                break;
            case 14:
                createSingletonComp("./tools/BackupManager.qml", "backupManagerInstance")
                break;
            case 15:
                createCompWrapped("./tools/TransferSpeedTest.qml")
                break;
            default:
            console.log(`No tool for id ${toolId}`)
        }


    }

    function deviceSelectionChanged(udid) {
        if (udid && udid.length) {
            App.DeviceContext.currentDeviceUdid = udid
        }
    }

    readonly property var mainToolsModel: ([
        {
            toolId: 0,
            title: qsTr("Airplayer"),
            description: qsTr("Cast your device screen"),
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/material-symbols_airplay-outline-rounded.svg",
            visible: true
        },
        {
            toolId: 1,
            title: qsTr("Simulate Location"),
            description: qsTr("Simulate GPS location on your device"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/material-symbols_location-on-outline.svg",
            visible: true
        },
        {
            toolId: 2,
            title: qsTr("Live Screen"),
            description: qsTr("View device screen in real-time"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/pepicons-print_cellphone-eye.svg",
            visible: true
        },
        {
            toolId: 3,
            title: qsTr("Query Mobile Gestalt"),
            description: qsTr("Query device hardware information"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/streamline_programming-browser-search-search-window-glass-app-code-programming-query-find-magnifying-apps.svg",
            visible: true
        },
        {
            toolId: 4,
            title: qsTr("Dev Disk Images"),
            description: qsTr("Manage developer disk images"),
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/tabler_database-export.svg",
            visible: true
        },
        {
            toolId: 5,
            title: qsTr("Wireless Gallery Import"),
            description: qsTr("Import photos wirelessly to your iDevice (requires Shortcuts app)"),
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/material-symbols_android-wifi-3-bar-plus.svg",
            visible: true
        },
        {
            toolId: 6,
            title: qsTr("iFuse Mount"),
            description: qsTr("Mount your iPhone's filesystem on your PC"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/fuse.svg",
            visible: (Qt.platform.os !== "osx" && Qt.platform.os !== "darwin")
        },
        {
            toolId: 7,
            title: qsTr("Cable Info"),
            description: qsTr("View detailed cable and connection info"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/material-symbols_cable-rounded.svg",
            visible: true
        },
        {
            toolId: 8,
            title: qsTr("Network Devices"),
            description: qsTr("Discover and monitor devices on your network"),
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/streamline_ultimate-multiple-users-network.svg",
            visible: true
        },
        {
            toolId: 15,
            title: qsTr("Transfer Speed Test"),
            description: qsTr("Measure upload and download speed to this device"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/material-symbols_cable-rounded.svg",
            visible: true
        }
    ])

    readonly property var moreToolsModel: ([
        {
            toolId: 14,
            title: qsTr("Backups"),
            description: qsTr("Back up and restore this device"),
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/tabler_database-export.svg",
            visible: true
        },
        {
            toolId: 9,
            title: qsTr("Mount Dev Image"),
            description: qsTr("Mount a compatible device image with a single click"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/mdi_disk.svg",
            visible: true
        },
        {
            toolId: 10,
            title: qsTr("Restart"),
            description: qsTr("Restart device services"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/ic_twotone-restart-alt.svg",
            visible: true
        },
        {
            toolId: 11,
            title: qsTr("Shutdown"),
            description: qsTr("Shut down the device"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/ic_outline-power-settings-new.svg",
            visible: true
        },
        {
            toolId: 12,
            title: qsTr("Recovery Mode"),
            description: qsTr("Enter device recovery mode"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/hugeicons_wrench-01.svg",
            visible: true
        },
        {
            toolId: 13,
            title: qsTr("Enable Wi-Fi Connections"),
            description: qsTr("Make device connectable via Wi-Fi"),
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/streamline-freehand_charging-flash-wireless.svg",
            visible: true
        }
    ])

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Device selection row
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 10

            Label {
                text: "Device:"
                Layout.alignment: Qt.AlignVCenter
            }

            ComboBox {
                id: deviceCombo
                Layout.minimumWidth: 230
                Layout.preferredWidth: 240
                enabled: root.hasDevice

                model: root.hasDevice ? App.DeviceContext.devices : [{ text: qsTr("No device connected"), udid: "" }]
                textRole: "text"
                valueRole: "udid"

                onActivated: (index) => {
                    const udid = deviceCombo.currentValue || ""
                    root.currentDeviceUdid = udid
                    root.deviceSelectionChanged(udid)
                }

                /* workaround to avoid connecting to devicecontext signal*/
                onCountChanged: {
                    if (count > 0) {
                        const lastIndex = count - 1
                        currentIndex = lastIndex
                        const udid = deviceCombo.valueAt(lastIndex) || ""
                        root.currentDeviceUdid = udid
                        root.deviceSelectionChanged(udid)
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 14
                Layout.margins: 0

                /* Section: Tools */
                Label {
                    text: "Tools"
                    font.bold: true
                    font.pixelSize: 14
                    leftPadding: 10
                }

                GridLayout {
                    id: mainGrid
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: root.mainToolsModel
                        delegate: ToolTile {
                            Layout.fillWidth: true
                            visible: modelData.visible

                            toolId: modelData.toolId
                            title: modelData.title
                            description: modelData.description
                            requiresDevice: modelData.requiresDevice
                            iconSource: modelData.iconSource

                            enabled: !requiresDevice || root.hasDevice

                            onClicked: {
                                root.toolClicked(toolId, requiresDevice)
                            }
                        }
                    }
                }

                /* More Tools */
                Label {
                    text: "More Tools"
                    font.bold: true
                    font.pixelSize: 14
                    leftPadding: 10
                    topPadding: 6
                }

                GridLayout {
                    id: moreGrid
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: root.moreToolsModel
                        delegate: ToolTile {
                            Layout.fillWidth: true
                            visible: modelData.visible

                            toolId: modelData.toolId
                            title: modelData.title
                            description: modelData.description
                            requiresDevice: modelData.requiresDevice
                            iconSource: modelData.iconSource

                            enabled: !requiresDevice || root.hasDevice

                            onClicked: {
                                root.toolClicked(toolId, requiresDevice)
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    component ToolTile: Rectangle {
        id: tile

        property int toolId: -1
        property string title: ""
        property string description: ""
        property bool requiresDevice: false
        property url iconSource: ""

        signal clicked()

        radius: 8
        color: "transparent"

        implicitHeight: 92

        opacity: enabled ? 1.0 : 0.45

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: tile.enabled
            cursorShape: tile.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: tile.clicked()
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            IconImage {
                id: icon
                source: tile.iconSource
                Layout.preferredHeight: 34
                Layout.preferredWidth: 34
                // FIXME: hardcoded accent color
                color: "#0078d7"
                opacity: tile.enabled ? 1.0 : 0.7
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: tile.title
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    text: tile.description
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    Layout.fillWidth: true
                    opacity: 0.85
                }
            }
        }
    }
}
