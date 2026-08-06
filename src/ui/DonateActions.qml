// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App

GridLayout {
    id: root

    property bool horizontal: false

    signal linkOpened

    columns: root.horizontal ? 2 : 1
    columnSpacing: 12
    rowSpacing: 12

    function openUrl(url) {
        Qt.openUrlExternally(url)
        root.linkOpened()
    }

    Button {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        text: qsTr("Sponsor with GitHub")
        icon.source: "qrc:/resources/icons/mdi_github.svg"
        icon.color: App.Theme.textSelected
        font.bold: true
        highlighted: true
        onClicked: root.openUrl(App.Constants.githubSponsorsUrl)
    }

    Button {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        text: qsTr("Support on Open Collective")
        icon.source: "qrc:/resources/icons/simple-icons_opencollective.svg"
        icon.color: App.Theme.text
        font.bold: true
        onClicked: root.openUrl(App.Constants.openCollectiveUrl)
    }
}
