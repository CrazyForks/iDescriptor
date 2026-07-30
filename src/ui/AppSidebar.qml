import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "." as App

Rectangle {
    id: root
    radius: 10

    property bool favoritesExpanded: true
    property bool devicesExpanded: true

    signal toggleRequested

    color: {
        switch (Qt.platform.os) {
            case "osx": return "transparent"
            case "windows": return App.Theme.sidebarBackgroundWindows
            default: return App.Theme.sidebarBackground
        }
    }
    implicitWidth: 200

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Qt.platform.os === "windows" ? 48 : 48

            IconImage {
                visible: Qt.platform.os !== "osx"
                id: welcomeLogo
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 10
                Layout.topMargin:10
                color: palette.text
                source: "qrc:/resources/icons/plain-icon.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Item {
                Layout.fillWidth: true
            }


            SidebarToggleButton {
                Layout.rightMargin: 10
                Layout.topMargin: Qt.platform.os !== "windows" ? 0 : 25
                // Layout.verticalCenter: parent.verticalCenter
                onClicked: root.toggleRequested()
            }
        }

        ScrollView {
            id: sidebarScroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: sidebarScroll.availableWidth
                height: Math.max(implicitHeight, sidebarScroll.availableHeight)
                spacing: 3

                SidebarSectionHeader {
                    Layout.topMargin: 2
                    text: qsTr("Favorites")
                    expanded: root.favoritesExpanded
                    onToggleRequested: root.favoritesExpanded = !root.favoritesExpanded
                }

                SidebarCollapsibleContent {
                    expanded: root.favoritesExpanded

                    SidebarDestinationButton {
                        text: qsTr("Welcome")
                        iconSource: "qrc:/resources/icons/material-symbols_home.svg"
                        selected: App.DeviceContext.currentDestination === "welcome"
                        onDestinationRequested: App.DeviceContext.selectWelcomePage()
                    }

                    SidebarDestinationButton {
                        text: qsTr("Apps")
                        iconSource: "qrc:/resources/icons/sidebar_app_store.svg"
                        selected: App.DeviceContext.currentDestination === "apps"
                        onDestinationRequested: App.DeviceContext.selectAppsPage()
                    }

                    SidebarDestinationButton {
                        text: qsTr("Toolbox")
                        iconSource: "qrc:/resources/icons/sidebar_toolbox.svg"
                        selected: App.DeviceContext.currentDestination === "toolbox"
                        onDestinationRequested: App.DeviceContext.selectToolboxPage()
                    }

                    SidebarDestinationButton {
                        text: qsTr("Jailbroken")
                        iconSource: "qrc:/resources/icons/sidebar_jailbroken.svg"
                        selected: App.DeviceContext.currentDestination === "jailbroken"
                        onDestinationRequested: App.DeviceContext.selectJailbrokenPage()
                    }
                }

                SidebarSectionHeader {
                    Layout.topMargin: 8
                    text: qsTr("Devices")
                    expanded: root.devicesExpanded
                    onToggleRequested: root.devicesExpanded = !root.devicesExpanded
                }

                SidebarCollapsibleContent {
                    expanded: root.devicesExpanded

                    Label {
                        visible: App.DeviceContext.getVisibleDeviceCount() === 0
                        Layout.fillWidth: true
                        Layout.leftMargin: App.Theme.sidebarHorizontalPadding
                        Layout.rightMargin: App.Theme.sidebarHorizontalPadding
                        Layout.topMargin: 2
                        text: qsTr("No connected devices")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: App.DeviceContext.devices

                        delegate: Item {
                            id: deviceDelegate

                            required property var model
                            readonly property var info: model.info

                            Layout.fillWidth: true
                            Layout.preferredHeight: deviceButton.implicitHeight
                            Layout.leftMargin: 7
                            Layout.rightMargin: 7

                            DeviceSidebarButton {
                                id: deviceButton
                                anchors.fill: parent
                                title: deviceDelegate.info.product_type
                                iconPath: deviceDelegate.info.placeholder_path
                                udid: deviceDelegate.info["UniqueDeviceID"]
                                wireless: deviceDelegate.info.is_wireless
                            }
                        }
                    }

                    Repeater {
                        model: App.DeviceContext.pendingDevices

                        delegate: Item {
                            id: pendingDelegate

                            required property var model

                            Layout.fillWidth: true
                            Layout.preferredHeight: pendingButton.implicitHeight
                            Layout.leftMargin: 7
                            Layout.rightMargin: 7

                            PendingDeviceSidebar {
                                id: pendingButton
                                anchors.fill: parent
                                udid: pendingDelegate.model.udid
                            }
                        }
                    }

                    Repeater {
                        model: App.DeviceContext.recoveryDevices

                        delegate: Item {
                            id: recoveryDelegate

                            required property var model
                            readonly property var info: model.info

                            Layout.fillWidth: true
                            Layout.preferredHeight: recoveryButton.implicitHeight
                            Layout.leftMargin: 7
                            Layout.rightMargin: 7

                            RecoveryDeviceSidebar {
                                id: recoveryButton
                                anchors.fill: parent
                                title: recoveryDelegate.model.text
                                deviceId: recoveryDelegate.model.id
                                mode: recoveryDelegate.info.mode
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        SidebarFooter {}
    }
}
