import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "." as App

Rectangle {
    id: root

    signal toggleRequested

    color: App.Theme.sidebarBackground
    implicitWidth: 200

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48

            SidebarToggleButton {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.toggleRequested()
            }
        }

        ScrollView {
            id: sidebarScroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: sidebarScroll.availableWidth
                height: Math.max(implicitHeight, sidebarScroll.availableHeight)
                spacing: 3

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: App.Theme.sidebarHorizontalPadding
                    Layout.rightMargin: App.Theme.sidebarHorizontalPadding
                    Layout.topMargin: 4
                    Layout.bottomMargin: 2
                    text: qsTr("Favorites")
                    color: App.Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Button {
                    id: welcomeButton

                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.preferredHeight: App.Theme.sidebarRowHeight
                    hoverEnabled: true
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 0
                    bottomPadding: 0
                    onClicked: {
                        App.DeviceContext.currentTab = 0;
                        App.DeviceContext.selectWelcomePage();
                    }

                    background: Rectangle {
                        radius: App.Theme.sidebarCornerRadius
                        color: App.DeviceContext.currentTab === 0 && App.DeviceContext.showWelcomePage ? App.Theme.selectionSoft : welcomeButton.down ? App.Theme.pressed : welcomeButton.hovered ? App.Theme.hover : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: App.Theme.fastAnimation
                            }
                        }
                    }

                    contentItem: RowLayout {
                        spacing: 8

                        IconImage {
                            source: "qrc:/resources/icons/material-symbols_home.svg"
                            color: App.Theme.icon
                            sourceSize.width: App.Theme.sidebarIconSize
                            sourceSize.height: App.Theme.sidebarIconSize
                            Layout.preferredWidth: App.Theme.sidebarIconSize
                            Layout.preferredHeight: App.Theme.sidebarIconSize
                            opacity: 0.82
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Welcome")
                            color: App.Theme.text
                            font.pixelSize: 13
                            font.weight: App.DeviceContext.currentTab === 0 && App.DeviceContext.showWelcomePage ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: App.Theme.sidebarHorizontalPadding
                    Layout.rightMargin: App.Theme.sidebarHorizontalPadding
                    Layout.topMargin: 12
                    Layout.bottomMargin: 2
                    text: qsTr("Devices")
                    color: App.Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Label {
                    visible: App.DeviceContext.getVisibleDeviceCount() === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: App.Theme.sidebarHorizontalPadding
                    Layout.rightMargin: App.Theme.sidebarHorizontalPadding
                    Layout.topMargin: 4
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

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: App.DeviceContext.currentTab = 0
                        }

                        SidebarTabButton {
                            id: deviceButton
                            anchors.fill: parent
                            currentSection: deviceDelegate.model.currentSection
                            title: deviceDelegate.info.product_type
                            iconPath: deviceDelegate.info.placeholder_path
                            udid: deviceDelegate.info["UniqueDeviceID"]
                            wireless: deviceDelegate.info.is_wireless
                            onSectionChanged: function (sectionIndex) {
                                if (deviceDelegate.model.currentSection !== sectionIndex)
                                    deviceDelegate.model.currentSection = sectionIndex;

                                App.DeviceContext.currentTab = 0;
                                App.DeviceContext.selectConnectedDevice(deviceDelegate.info["UniqueDeviceID"]);
                            }
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

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: App.DeviceContext.currentTab = 0
                        }

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

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: App.DeviceContext.currentTab = 0
                        }

                        RecoveryDeviceSidebar {
                            id: recoveryButton
                            anchors.fill: parent
                            title: recoveryDelegate.model.text
                            deviceId: recoveryDelegate.model.id
                            mode: recoveryDelegate.info.mode
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
