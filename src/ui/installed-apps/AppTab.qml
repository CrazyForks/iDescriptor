// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Button {
    id: root

    required property var device
    required property string appName
    required property string bundleId
    property string version: ""
    required property string iconSource
    property bool selected: false

    signal appClicked(string bundleId)

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: contentRow.implicitHeight + 16
    height: implicitHeight
    padding: 0
    hoverEnabled: true
    enabled: true
    onClicked: root.appClicked(root.bundleId)

    Component.onCompleted: {
        device.sb_client.fetch_app_icon(root.bundleId)
    }

    background: Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.selected ? Theme.selection : (root.hovered ? Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.1) : Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.06))
        border.width: 1
        border.color: root.selected ? Qt.lighter(palette.highlight, 1.15) : Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.12)
    }

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 10


        IconLoader {
            id: iconImg
            iconSource: root.iconSource
            // visible: root.iconSource.length > 0 && status === Image.Ready
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: root.appName
                color: root.selected ? Theme.textSelected : palette.text
                font.weight: Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
              Layout.fillWidth: true
              text: root.bundleId
              color: root.selected ? Qt.rgba(palette.highlightedText.r, palette.highlightedText.g, palette.highlightedText.b, 0.75) : Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.62)
              font.weight: Font.Light
              font.pixelSize: 10
              elide: Text.ElideRight
              maximumLineCount: 1
            }


            Text {
                Layout.fillWidth: true
                text: root.version
                color: root.selected ? Qt.rgba(palette.highlightedText.r, palette.highlightedText.g, palette.highlightedText.b, 0.75) : Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.62)
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: root.version.length > 0
            }

        }

    }

}
