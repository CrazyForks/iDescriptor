import QtQuick
import QtQuick.Layouts
import "." as App

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            AppSidebar {
                id: sidebar

                visible: App.DeviceContext.sidebarVisible
                Layout.fillHeight: true
                Layout.minimumWidth: 180
                Layout.preferredWidth: Math.round(root.width * 0.2)
                Layout.maximumWidth: 260
                onToggleRequested: App.DeviceContext.sidebarVisible = false
            }

            Rectangle {
                visible: App.DeviceContext.sidebarVisible
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: App.Theme.sidebarDivider
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    spacing: 0

                    SidebarToggleButton {
                        visible: !App.DeviceContext.sidebarVisible
                        // The macOS traffic lights occupy x=20...74. Keep the
                        // collapsed-sidebar control beside them, not below them.
                        Layout.leftMargin: Qt.platform.os === "osx" ? 84 : 10
                        Layout.rightMargin: 4
                        onClicked: App.DeviceContext.sidebarVisible = true
                    }

                    App.TabButton {
                        text: qsTr("Apps")
                        onClicked: App.DeviceContext.currentTab = 1
                        active: App.DeviceContext.currentTab === 1
                    }

                    App.TabButton {
                        text: qsTr("Toolbox")
                        onClicked: App.DeviceContext.currentTab = 2
                        active: App.DeviceContext.currentTab === 2
                    }

                    App.TabButton {
                        text: qsTr("Jailbroken")
                        onClicked: App.DeviceContext.currentTab = 3
                        active: App.DeviceContext.currentTab === 3
                    }
                }

                Tabs {
                    currentIndex: App.DeviceContext.currentTab
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                StatusBar {}
            }
        }
    }
}
