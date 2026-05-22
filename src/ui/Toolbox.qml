import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Dialogs
import "." as App

Item {
    id: root
    anchors.fill: parent

    MessageDialog {
        id: errorDialog
        title: "Error"
        text: ""
    }

    property string currentDeviceUdid: ""
    readonly property bool hasDevice: App.DeviceContext.devices && App.DeviceContext.devices.count > 0
    
    function createComp(loc, args = {}) {
        const comp = Qt.createComponent(loc)
        if (comp.status === Component.Ready) {
            const win = comp.createObject(root,args)    
            if (win !== null) {
                win.show()
            } else {
                console.error("createObject failed:", comp.errorString())
            }

        } else if (comp.status === Component.Error) {
            console.error("Component failed to load:", comp.errorString())
        }
    }

    // 0 Airplayer, 1 VirtualLocation, 2 LiveScreen, 3 QueryMobileGestalt, 4 DeveloperDiskImages,
    // 5 WirelessGalleryImport, 6 iFuse, 7 CableInfo, 8 NetworkDevices, 9 MountDevImage,
    // 10 Restart, 11 Shutdown, 12 RecoveryMode, 13 EnableWifiConnections
    // signal toolClicked(int toolId, bool requiresDevice)
    function toolClicked(toolId, requiresDevice) {
        const device = App.DeviceContext.getDevice(currentDeviceUdid)
        
        if (requiresDevice) {
            if (!device) {
                console.log("DEVICE DISAPPERED")
                return
            }
        }

        const createCompWrapped = (loc) => {
            return createComp(loc, {
                device,
                udid: currentDeviceUdid
            })
        }

        switch (toolId) {
            case 0: 
                const gl_plugin_loaded = AirplayImp.load_gst_gl()
                if (!gl_plugin_loaded) {
                    switch (Qt.platform.os) {
                        case "linux":
                            errorDialog.text = qsTr("Failed to load gst gl plugin, make sure you are using QT_QPA_PLATFORM=xcb env")
                            break;
                        case "windows":
                            errorDialog.text = qsTr("Failed to load gst gl plugin, make sure you can use OpenGL")
                            break;
                        case "macos":
                            // FIXME:
                            errorDialog.text = qsTr("FIXME?")
                            break;
                        default:
                            errorDialog.text = qsTr("Failed to load gst gl plugin")

                    }
                    errorDialog.open()
                    return;
                }

                createCompWrapped("./tools/Airplay.qml")
                break;
            case 1: 
                createCompWrapped("./tools/VirtualLocation.qml")
                break;
            case 3:
                // FIXME: doesnt work iOS 17 and above
                createCompWrapped("./tools/QueryMobileGestalt.qml")
                break;
            case 7:
                createCompWrapped("./tools/CableInfo.qml")
                break;

            default:
            console.log(`No tool for id ${toolId}`)
        }

        
    }

    signal deviceSelectionChanged(string udid)

    readonly property var mainToolsModel: ([
        {
            toolId: 0,
            title: "Airplayer",
            description: "Cast your device screen",
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/material-symbols_airplay-outline-rounded.svg",
            visible: true
        },
        {
            toolId: 1,
            title: "Virtual Location",
            description: "Simulate GPS location on your device",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/material-symbols_location-on-outline.svg",
            visible: true
        },
        {
            toolId: 2,
            title: "Live Screen",
            description: "View device screen in real-time",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/pepicons-print_cellphone-eye.svg",
            visible: true
        },
        {
            toolId: 3,
            title: "Query Mobile Gestalt",
            description: "Query device hardware information",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/streamline_programming-browser-search-search-window-glass-app-code-programming-query-find-magnifying-apps.svg",
            visible: true
        },
        {
            toolId: 4,
            title: "Dev Disk Images",
            description: "Manage developer disk images",
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/tabler_database-export.svg",
            visible: true
        },
        {
            toolId: 5,
            title: "Wireless Gallery Import",
            description: "Import photos wirelessly to your iDevice (requires Shortcuts app)",
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/material-symbols_android-wifi-3-bar-plus.svg",
            visible: true
        },
        {
            toolId: 6,
            title: "iFuse Mount",
            description: "Mount your iPhone's filesystem on your PC",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/fuse.png",
            visible: (Qt.platform.os !== "osx" && Qt.platform.os !== "darwin")
        },
        {
            toolId: 7,
            title: "Cable Info",
            description: "View detailed cable and connection info",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/material-symbols_cable-rounded.svg",
            visible: true
        },
        {
            toolId: 8,
            title: "Network Devices",
            description: "Discover and monitor devices on your network",
            requiresDevice: false,
            iconSource: "qrc:/resources/icons/streamline_ultimate-multiple-users-network.svg",
            visible: true
        }
    ])

    readonly property var moreToolsModel: ([
        {
            toolId: 9,
            title: "Mount Dev Image",
            description: "Mount a compatible device image with a single click",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/mdi_disk.svg",
            visible: true
        },
        {
            toolId: 10,
            title: "Restart",
            description: "Restart device services",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/ic_twotone-restart-alt.svg",
            visible: true
        },
        {
            toolId: 11,
            title: "Shutdown",
            description: "Shut down the device",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/ic_outline-power-settings-new.svg",
            visible: true
        },
        {
            toolId: 12,
            title: "Recovery Mode",
            description: "Enter device recovery mode",
            requiresDevice: true,
            iconSource: "qrc:/resources/icons/hugeicons_wrench-01.svg",
            visible: true
        },
        {
            toolId: 13,
            title: "Enable Wi-Fi Connections",
            description: "Make device connectable via Wi-Fi",
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
                Layout.minimumWidth: 260
                Layout.preferredWidth: 320
                enabled: root.hasDevice

                model: root.hasDevice ? App.DeviceContext.devices : [{ text: "No device connected", udid: "" }]
                textRole: "text"
                valueRole: "udid"

                onActivated: (index) => {
                    console.log("ComboBox activated")
                    const udid = deviceCombo.currentValue || ""
                    root.currentDeviceUdid = udid
                    root.deviceSelectionChanged(udid)
                }

                /* workaround to avoid connecting to deviceocntext signal*/
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

        // Rectangle {
        //     // subtle hover overlay
        //     anchors.fill: parent
        //     radius: tile.radius
        //     color: mouse.containsMouse && tile.enabled ? "#ffffff" : "transparent"
        //     opacity: 0.05
        // }

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

            Image {
                id: icon
                source: tile.iconSource

                Layout.preferredHeight: 34
                Layout.preferredWidth: 34

                // FIXME:theming
                // color: "black"
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