// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "." as App

Item {
    id: root

    property string title: ""
    property string udid: ""
    required property string iconPath
    required property bool wireless
    readonly property bool selectedDevice:
        App.DeviceContext.currentDestination === "device"
        && App.DeviceContext.currentDestinationId === root.udid
    readonly property string displayTitle:
        title && title.length ? title : qsTr("Unknown device")

    implicitWidth: 175
    implicitHeight: 42

    function selectDevice() {
        App.DeviceContext.selectConnectedDevice(root.udid)
    }

    Menu {
        id: contextMenu

        MenuItem {
            text: qsTr("Restart")
            enabled: root.udid.length > 0
            onTriggered: App.Toolbox.requestDeviceAction("restart", root.udid)
        }

        MenuItem {
            text: qsTr("Shut Down")
            enabled: root.udid.length > 0
            onTriggered: App.Toolbox.requestDeviceAction("shutdown", root.udid)
        }

        MenuItem {
            text: qsTr("Recovery Mode")
            enabled: root.udid.length > 0
            onTriggered: App.Toolbox.requestDeviceAction("recovery", root.udid)
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Unpair")
            enabled: root.udid.length > 0
            onTriggered: App.Toolbox.requestDeviceAction("unpair", root.udid)
        }

        MenuItem {
            text: qsTr("Unpair and Remove")
            enabled: root.udid.length > 0
            onTriggered: App.Toolbox.requestDeviceAction("unpairAndRemove", root.udid)
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Remove")
            enabled: root.udid.length > 0
            onTriggered: App.DeviceContext.removeDevice(root.udid)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: App.Theme.sidebarCornerRadius
        color: root.selectedDevice ? App.Theme.sidebarSelection
                                   : deviceHover.hovered ? App.Theme.hover
                                                         : "transparent"

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }

        HoverHandler { id: deviceHover }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.selectDevice()
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: function(point) {
                contextMenu.x = point.position.x
                contextMenu.y = point.position.y
                contextMenu.open()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 7

            Image {
                source: root.iconPath
                sourceSize.width: 27
                sourceSize.height: 27
                Layout.preferredWidth: 27
                Layout.preferredHeight: 27
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.displayTitle
                color: App.Theme.text
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            IconImage {
                visible: root.wireless
                source: "qrc:/resources/icons/qlementine-icons_wireless-1-16.svg"
                color: App.Theme.icon
                sourceSize.width: 15
                sourceSize.height: 15
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
                opacity: 0.75
            }
        }
    }
}
