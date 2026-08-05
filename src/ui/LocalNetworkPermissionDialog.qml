// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "./base"
import "." as App

AnimatedDialog {
    id: root

    signal continueRequested()

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    standardButtons: Dialog.NoButton
    closePolicy: Popup.NoAutoClose
    width: Math.min(500, parent ? parent.width - 32 : 500)
    height: Math.min(550, parent ? parent.height - 32 : 550)

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        Label {
            Layout.fillWidth: true
            text: qsTr("Allow for Local Network Discovery")
            color: App.Theme.text
            font.pixelSize: 22
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("macOS will ask for permission next. Choose Allow so iDescriptor can find and connect to Apple devices over Wi-Fi.")
            color: App.Theme.textMuted
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Image {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // anchors.fill: parent
            // anchors.margins: 10
            source: "qrc:/resources/local-network-consent.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }


        Button {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            text: qsTr("Continue")
            highlighted: true
            font.bold: true
            onClicked: root.continueRequested()
        }
    }
}
