// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import ".." as App

SplitView {
    id: root

    spacing: 0

    handle: Rectangle {
        implicitWidth: 7
        implicitHeight: 7
        radius: 10
        color: SplitHandle.pressed
               ? App.Theme.focus
               : SplitHandle.hovered
                 ? App.Theme.selectionStroke
                 : App.Theme.sidebarDivider

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }

        Rectangle {
            anchors.centerIn: parent
            width: root.orientation === Qt.Horizontal ? 1 : parent.width
            height: root.orientation === Qt.Horizontal ? parent.height : 1
            color: App.Theme.sidebarDivider
        }
    }
}
