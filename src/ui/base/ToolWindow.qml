// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".." as App


DefaultWindow {
    id: root
    required property string udid
    required property var device
    property bool auto_close: true

    Component.onCompleted : {
        if (Qt.platform.os === "osx") {
            QmlUtils.setup_tool_window(root.contentItem.Window.window)
        }
    }

    Connections {
        target: App.DeviceContext
        enabled: root.auto_close

        function onDeviceRemoved(removedUdid) {
            if (root.udid === removedUdid)
                root.close()
        }
    }
}
