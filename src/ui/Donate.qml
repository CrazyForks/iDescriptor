import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "./base"
import "." as App

Item {
    id: root
    clip: true

    ScrollView {
        id: donateScroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.min(720, Math.max(0, donateScroll.availableWidth - 48))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Item { Layout.preferredHeight: 24 }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                radius: width / 2
                color: Qt.rgba(1, 55 / 255, 95 / 255, App.Theme.darkMode ? 0.2 : 0.12)

                IconImage {
                    anchors.centerIn: parent
                    source: "qrc:/resources/icons/material-symbols_favorite.svg"
                    color: "#ff375f"
                    sourceSize: Qt.size(36, 36)
                    width: 36
                    height: 36
                }
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Support iDescriptor")
                color: App.Theme.text
                font.pixelSize: 28
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Your support helps fund ongoing development, testing, and the features the community cares about most.")
                color: App.Theme.textMuted
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Item { Layout.preferredHeight: 4 }

            SectionBox {
                Layout.fillWidth: true
                padding: 16
                contentSpacing: 12

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Choose how you would like to support the project.")
                    color: App.Theme.textMuted
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                DonateActions {
                    Layout.fillWidth: true
                    horizontal: root.width >= 620
                }
            }

            Item { Layout.preferredHeight: 24 }
        }
    }
}
