import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App

Item {
    id: root

    // FIXME: theming
    property color linkColor: "#3b82f6"

    CustomPairingDialog {
        id: customPairingDialog
        anchors.centerIn: parent
    }

    ColumnLayout {
        id: mainLayout
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        y: Math.max(10, Math.round((parent.height - implicitHeight) / 2))
        spacing: 0

        Text {
            id: title
            Layout.fillWidth: true
            text: qsTr("Welcome to iDescriptor")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 28
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            color: palette.text
        }

        Item { Layout.preferredHeight: 6 }

        Text {
            id: subtitle
            Layout.fillWidth: true
            text: qsTr("Open-Source & Free")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 10
            font.weight: Font.Normal
            wrapMode: Text.WordWrap
            color: palette.text
        }

        Item { Layout.preferredHeight: 12 }

        RowLayout {
            id: imageAndWirelessDevicesLayout
            Layout.alignment: Qt.AlignHCenter
            spacing: 0

            Item { Layout.preferredWidth: 75 }

            Item {
                id: connectImageSlot
                readonly property real imageAspectRatio: 191 / 428

                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Math.min(320, Math.max(220, mainLayout.width * 0.65))
                Layout.preferredHeight: Math.min(520, Math.max(360, mainLayout.height * 0.65))

                Image {
                    id: connectImage
                    anchors.centerIn: parent
                    source: "qrc:/resources/connect.png"
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                    smooth: true

                    height: Math.min(parent.height, parent.width / connectImageSlot.imageAspectRatio)
                    width: height * connectImageSlot.imageAspectRatio
                }
            }

            Item { Layout.preferredWidth: 75 }

            ColumnLayout {
                id: explorerWithInstructionLayout
                Layout.preferredWidth: 500
                Layout.maximumWidth: 600
                Layout.preferredHeight: 600
                spacing: 12

                NetworkDevicesToConnect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Connect with pairing file")
                    icon.source: "qrc:/resources/icons/ic_baseline-insert-drive-file.svg"
                    icon.width: 16
                    icon.height: 16
                    onClicked: customPairingDialog.open()

                    background: Rectangle {
                        radius: 12
                        color: parent.down ? App.Theme.pressed
                              : parent.hovered ? App.Theme.hover
                                               : App.Theme.softBg
                        border.color: App.Theme.controlStroke
                        border.width: 1
                    }
                }

                Text {
                    id: howToConnectLink
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("How to connect a wireless device?")
                    color: root.linkColor
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            try {
                                const comp = Qt.createComponent("HowToConnect.qml")
                                const win = comp.createObject(root)
                                win.open()
                            } catch(e) {
                                console.log("errror",e)
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 20 }
            }
        }

        Item { Layout.preferredHeight: 10 }

        Text {
            id: instruction
            Layout.fillWidth: true
            text: qsTr("Connect an iDevice to get started")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            color: palette.text
        }

        Item { Layout.preferredHeight: 10 }

        Text {
            id: githubLink
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Found an issue? Report it on GitHub")
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

        Loader {
            Layout.alignment: Qt.AlignHCenter
            visible: Qt.platform.os !== "osx"
            active: visible
            source: active ? "Diagnose.qml" : ""
            Layout.preferredWidth: item ? item.implicitWidth : 520
            Layout.preferredHeight: item ? item.implicitHeight : 0
        }
    }
}
