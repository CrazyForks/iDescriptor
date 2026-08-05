// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App

Item {
    id: root

    property string title: ""
    property string deviceId: ""
    required property string mode
    required property string iconPath
    readonly property bool selectedDevice:
        App.DeviceContext.currentDestination === "recoveryDevice"
        && App.DeviceContext.currentDestinationId === deviceId
    readonly property string displayTitle: title && title.length ? title : qsTr("Recovery Device")

    implicitWidth: 200
    implicitHeight: card.implicitHeight

    // TODO: maybe we can do better here
    function selectDevice() {
        App.DeviceContext.selectRecoveryDevice(root.deviceId)
    }

    Rectangle {
        id: card
        width: root.width
        implicitHeight: contentColumn.implicitHeight + 10
        radius: App.Theme.sidebarCornerRadius
        color: root.selectedDevice
            ? App.Theme.sidebarSelection
            : cardHover.hovered ? App.Theme.hover : "transparent"

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }

        HoverHandler { id: cardHover }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5

            Image {
                source: root.iconPath
                sourceSize.width: 30
                sourceSize.height: 30
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            ColumnLayout {
                id: contentColumn
                spacing: 5

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: headerColumn.implicitHeight

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: root.selectDevice()
                    }

                    ColumnLayout {
                        id: headerColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Label {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.displayTitle
                            color: App.Theme.text
                            font.bold: true
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.mode
                            color: App.Theme.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
