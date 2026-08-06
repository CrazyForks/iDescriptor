// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import "../"


Control {
    id: section
    property string title: ""
    default property alias content: body.data
    property alias overlay: overlayLayer.data
    property int contentSpacing: 8
    property int titleSpacing: 6
    readonly property bool hasTitle: title.length > 0

    padding: 10
    implicitWidth: Math.max(titleLabel.implicitWidth, body.implicitWidth) + leftPadding + rightPadding
    implicitHeight: titleLabel.height + (hasTitle ? titleSpacing : 0) + body.implicitHeight + topPadding + bottomPadding

    background: Rectangle {
        color: Theme.softBg
        border.color: Theme.softBgBorder
        border.width: 1
        radius: 10
    }

    contentItem: Item {
        implicitWidth: Math.max(titleLabel.implicitWidth, body.implicitWidth)
        implicitHeight: titleLabel.height + (section.hasTitle ? section.titleSpacing : 0) + body.implicitHeight

        Label {
            id: titleLabel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: section.hasTitle ? implicitHeight : 0
            text: section.title
            font.pixelSize: 15
            font.bold: true
            visible: section.hasTitle
        }

        ColumnLayout {
            id: body
            anchors.top: titleLabel.bottom
            anchors.topMargin: section.hasTitle ? section.titleSpacing : 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: section.contentSpacing
        }
    }

    Item {
        id: overlayLayer
        anchors.fill: parent
        z: 1
    }
}
