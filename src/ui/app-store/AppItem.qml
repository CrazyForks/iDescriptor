import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt5Compat.GraphicalEffects
import QtQuick.Controls.impl 
import ".."

Rectangle {
    required property var name;
    required property var bundleId;
    required property var description;
    required property var logoUrl;
    required property var websiteUrl;
    required property var useBundleIdForIcon;
    required property var sponsorLabel;
    required property var sponsorColor;
    
    id: root
    width: grid.cellWidth - 20
    height: grid.cellHeight - 20
    radius: 8
    border.color: "#ddd"
    color: "transparent"

    property string iconSource: ""

    Component.onCompleted: {
        console.log("Name:", root.name)
        if (root.logoUrl && !root.useBundleIdForIcon) {
            iconSource = root.logoUrl;
        } else if (root.bundleId) {
            Helpers.fetchAppIconFromApple(root.bundleId, function(url) { iconSource = url; });
        }
    }

    RowLayout {
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
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: root.name
                    font.pixelSize: 16
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }

                Rectangle {
                    visible: root.sponsorLabel && root.sponsorLabel.length > 0
                    color: root.sponsorColor
                    radius: 4
                    height: 16

                    Label {
                        anchors.centerIn: parent
                        text: root.sponsorLabel
                        font.pixelSize: 10
                        color: "#333"
                        padding: 4
                    }
                }
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
                text: "Install"
                font.pixelSize: 12
                font.bold: true
                background: Rectangle {
                    color:  "#0076FF"
                    radius: 4
                }
            }

            Button {
                // FIXME: move this logic to another qml file
                text: (root.websiteUrl && root.websiteUrl.length) ? "Website" : "Get IPA"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

}