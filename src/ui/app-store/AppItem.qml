// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    required property var name
    required property var bundleId
    required property var description

    signal installRequested(string bundleId, string appName)
    signal getIpaRequested(string bundleId, string appName)

    id: root
    implicitWidth: 260
    implicitHeight: 128
    radius: 8
    color: "transparent"

    property string iconSource: ""
    signal selected(var app)


    Component.onCompleted: {
        Helpers.fetchAppIconFromApple(root.bundleId, function(url) { iconSource = url; });
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        cursorShape: Qt.PointingHandCursor

        onClicked: root.selected({
            name: root.name,
            bundleId: root.bundleId,
            description: root.description,
            logoUrl: root.logoUrl,
            websiteUrl: root.websiteUrl,
            useBundleIdForIcon: root.useBundleIdForIcon
        })
    }

    RowLayout {
        z: 1
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        IconLoader {
            iconSource: root.iconSource
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 6


            RowLayout {
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6

                    Label {
                        text: root.name
                        font.pixelSize: 16
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }

                    Label {
                        text: root.description
                        color: "#666"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }

                ColumnLayout {
                    spacing: 6
                        // FIXME: wire up click handling
                    Layout.alignment: Qt.AlignCenter
                    Layout.minimumWidth: implicitWidth

                    Button {
                        Layout.alignment: Qt.AlignCenter
                        id : installButton
                        contentItem: Text {
                            text: qsTr("Install")
                            color: Theme.textSelected
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        font.pixelSize: 12

                        font.bold: true
                        background: Rectangle {
                            color:  installButton.down ? Theme.pressed
                                                 : installButton.hovered ? Theme.accentHover
                                                                        : Theme.accent
                            radius: 4
                        }
                        onClicked: {
                            root.installRequested(root.bundleId, root.name)
                        }
                    }

                    Button {
                        // FIXME: move this logic to another qml file
                        text: (root.websiteUrl && root.websiteUrl.length) ? qsTr("Website") : qsTr("Get IPA")
                        font.pixelSize: 12
                        font.bold: true
                        onClicked: {
                            if (root.websiteUrl && root.websiteUrl.length) {
                                Qt.openUrlExternally(root.websiteUrl)
                            } else {
                                root.getIpaRequested(root.bundleId, root.name)
                            }
                        }
                    }
                }

            }

            Rectangle {
                Layout.preferredHeight: 1
                color: Theme.separator
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 10
            }
        }
    }

}
