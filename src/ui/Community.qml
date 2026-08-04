pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "./base"
import "." as App

Item {
    id: root
    clip: true

    readonly property var communityLinks: [
        {
            title: qsTr("GitHub"),
            description: qsTr("View the source code, report issues, and contribute to iDescriptor."),
            actionText: qsTr("Open GitHub"),
            iconSource: "qrc:/resources/icons/mdi_github.svg",
            iconColor: "",
            iconBackground: App.Theme.softBg,
            url: App.Constants.repoUrl
        },
        {
            title: qsTr("LinkedIn"),
            description: qsTr("Follow iDescriptor project updates on LinkedIn."),
            actionText: qsTr("Open LinkedIn"),
            iconSource: "qrc:/resources/icons/simple-icons_linkedin.svg",
            iconColor: "#0a66c2",
            iconBackground: Qt.rgba(10 / 255, 102 / 255, 194 / 255, App.Theme.darkMode ? 0.22 : 0.12),
            url: App.Constants.linkedinUrl
        },
        {
            title: qsTr("Reddit"),
            description: qsTr("Join discussions with the iDescriptor community on Reddit."),
            actionText: qsTr("Open Reddit"),
            iconSource: "qrc:/resources/icons/simple-icons_reddit.svg",
            iconColor: "#ff4500",
            iconBackground: Qt.rgba(1, 69 / 255, 0, App.Theme.darkMode ? 0.22 : 0.12),
            url: App.Constants.redditUrl
        }
    ]

    ScrollView {
        id: communityScroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.min(960, Math.max(0, communityScroll.availableWidth - 48))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Item { Layout.preferredHeight: 24 }

            Label {
                Layout.fillWidth: true
                text: qsTr("Join the iDescriptor Community")
                color: App.Theme.text
                font.pixelSize: 28
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Follow development, connect with other users, and share feedback.")
                color: App.Theme.textMuted
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Item { Layout.preferredHeight: 4 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Repeater {
                    model: root.communityLinks

                    delegate: SectionBox {
                        id: communityCard
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 248
                        padding: 18
                        contentSpacing: 12

                        background: Rectangle {
                            color: App.Theme.elevatedSurface
                            border.color: App.Theme.separator
                            border.width: 1
                            radius: 16
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 54
                            Layout.preferredHeight: 54
                            radius: 14
                            color: communityCard.modelData.iconBackground

                            IconImage {
                                anchors.centerIn: parent
                                source: communityCard.modelData.iconSource
                                color: communityCard.modelData.iconColor.length > 0
                                       ? communityCard.modelData.iconColor : App.Theme.icon
                                sourceSize: Qt.size(30, 30)
                                width: 30
                                height: 30
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: communityCard.modelData.title
                            color: App.Theme.text
                            font.pixelSize: 18
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: communityCard.modelData.description
                            color: App.Theme.textMuted
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignTop
                            wrapMode: Text.WordWrap
                        }

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            text: communityCard.modelData.actionText
                            flat: true
                            onClicked: Qt.openUrlExternally(communityCard.modelData.url)
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 24 }
        }
    }
}
