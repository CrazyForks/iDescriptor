// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../" as App

Control {
    id: root

    property string labelText: qsTr("Location")
    property string location: ""
    property bool changeEnabled: true
    property bool changeVisible: true

    signal changeRequested()

    padding: 0
    implicitHeight: 54

    background: Rectangle {
        radius: 7
        color: App.Theme.rowSurface
        border.color: App.Theme.controlStroke
        border.width: 1
    }

    contentItem: RowLayout {
        spacing: 12

        Label {
            Layout.leftMargin: 12
            text: root.labelText
            color: App.Theme.text
            font.weight: Font.DemiBold
        }

        Label {
            id: locationLabel
            Layout.fillWidth: true
            text: root.location
            color: App.Theme.systemBlue
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            font.underline: locationHover.hovered

            TapHandler {
                enabled: root.location.length > 0
                onTapped: Qt.openUrlExternally(App.Helpers.toFileUrl(root.location))
            }

            HoverHandler {
                id: locationHover
                enabled: root.location.length > 0
                cursorShape: Qt.PointingHandCursor
            }
        }

        Button {
            Layout.rightMargin: 8
            visible: root.changeVisible
            enabled: root.changeEnabled
            text: qsTr("Change…")
            onClicked: root.changeRequested()
        }
    }
}
