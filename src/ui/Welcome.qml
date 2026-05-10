import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    anchors.fill: parent

    // FIXME: theming
    property color linkColor: "#3b82f6"


    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: 0

        Item { Layout.preferredHeight: 10 }

        Item { Layout.fillHeight: true }

        Text {
            id: title
            Layout.fillWidth: true
            text: "Welcome to iDescriptor"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 28
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            color: "white"
        }

        Item { Layout.preferredHeight: 6 }

        Text {
            id: subtitle
            Layout.fillWidth: true
            text: "Open-Source & Free"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 10
            font.weight: Font.Normal
            wrapMode: Text.WordWrap
            // color: palette.text
        }

        Item { Layout.preferredHeight: 12 }

        RowLayout {
            id: imageAndWirelessDevicesLayout
            Layout.alignment: Qt.AlignHCenter
            spacing: 75

            Image {
                id: connectImage
                source: "qrc:/resources/connect.png"
                fillMode: Image.PreserveAspectFit
                mipmap: true
                smooth: true

                sourceSize.width: 0
                sourceSize.height: 0
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
            }

            ColumnLayout {
                id: explorerWithInstructionLayout
                spacing: 12

                // FIXME: implement
                Rectangle {
                    Layout.preferredWidth: 360
                    Layout.preferredHeight: 180
                    radius: 8
                    color: "#1e40af" // blue
                    border.color: "#0b2a7a"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "NetworkDevicesToConnectWidget"
                        color: "white"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    id: howToConnectLink
                    Layout.alignment: Qt.AlignHCenter
                    text: "How to connect a wireless device?"
                    color: root.linkColor
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.howToConnectRequested()
                    }
                }

                Item { Layout.preferredHeight: 20 }
            }
        }

        Item { Layout.preferredHeight: 10 }

        Text {
            id: instruction
            Layout.fillWidth: true
            text: "Connect an iDevice to get started"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            // color: palette.text
        }

        Item { Layout.preferredHeight: 10 }

        Text {
            id: githubLink
            Layout.alignment: Qt.AlignHCenter
            text: "Found an issue? Report it on GitHub"
            color: root.linkColor
            font.pixelSize: 12
            font.weight: Font.DemiBold
            wrapMode: Text.NoWrap

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(CONSTANTS.REPO_URL)
            }
        }

        Item { Layout.preferredHeight: 10 }

        // FIXME: implement
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: Qt.platform.os !== "osx"
            Layout.preferredWidth: 520
            Layout.preferredHeight: 90
            radius: 8
            color: "#b91c1c" // red
            border.color: "#7f1d1d"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "DiagnoseWidget"
                color: "white"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
        }

        // bottom stretch
        Item { Layout.fillHeight: true }
    }
}
