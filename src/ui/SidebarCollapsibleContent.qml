// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property bool expanded: true
    property real contentSpacing: 3
    property real expansionProgress: expanded ? 1 : 0
    default property alias contentData: contentColumn.data

    Layout.fillWidth: true
    Layout.minimumHeight: root.implicitHeight
    Layout.preferredHeight: root.implicitHeight
    Layout.maximumHeight: root.implicitHeight
    implicitHeight: contentColumn.implicitHeight * root.expansionProgress
    clip: true

    Behavior on expansionProgress {
        NumberAnimation {
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }

    ColumnLayout {
        id: contentColumn

        width: root.width
        y: -(1 - root.expansionProgress) * implicitHeight
        spacing: root.contentSpacing
    }
}
