// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick 
import QtQuick.Controls 
import QtQuick.Layouts 

Item {
    id: root
    required property int index
    required property int currentIndex
    property bool isActive : root.currentIndex === index

    visible : currentIndex == index
    opacity: isActive ? 1 : 0
    property real slideY: isActive ? 0 : 20
    transform: Translate { y: root.slideY }

    Behavior on opacity {
        NumberAnimation { duration: 167; easing.type: Easing.OutCubic }
    }
    Behavior on slideY {
        NumberAnimation { duration: 167; easing.type: Easing.OutCubic }
    }
}
