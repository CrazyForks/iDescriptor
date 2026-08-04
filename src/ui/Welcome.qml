import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.impl
import QtQuick.Dialogs
import "." as App

Item {
    id: root

    // FIXME: theming
    property color linkColor: "#3b82f6"

    CustomPairingDialog {
        id: customPairingDialog
    }

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 0

        RowLayout {
            spacing: 5
            Layout.alignment: Qt.AlignHCenter

            Text {
                id: title
                text: qsTr("Welcome to iDescriptor")
                font.pixelSize: 28
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                color: palette.text
            }

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
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 280
            spacing: 24

            Item {
                Layout.fillWidth: true
            }

            Item {
                id: connectImageSlot
                readonly property real imageAspectRatio: 1 / 1

                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: true
                Layout.minimumWidth: 150
                Layout.preferredWidth: Math.min(280, Math.max(150, imageAndWirelessDevicesLayout.height
                                                                  * connectImageSlot.imageAspectRatio))
                Layout.maximumWidth: 280

                Image {
                    id: connectImage
                    anchors.fill: parent
                    //source: "qrc:/resources/connect.png"
                    source: "qrc:/resources/welcome-connect.png"
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                    smooth: true
                }
            }

            ColumnLayout {
                id: explorerWithInstructionLayout
                Layout.fillHeight: true
                Layout.minimumWidth: 320
                Layout.preferredWidth: 500
                Layout.maximumWidth: 600
                spacing: 12

                NetworkDevicesToConnect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                Button {
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("Connect with pairing file")
                    icon.source: "qrc:/resources/icons/ic_baseline-insert-drive-file.svg"
                    icon.width: 16
                    icon.height: 16
                    icon.color: palette.text
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
                    Layout.alignment: Qt.AlignRight
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

            }

            Item {
                Layout.fillWidth: true
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

        Loader {
            id: diagnosticsLoader
            active: Qt.platform.os !== "osx"
            source: active ? "Diagnose.qml" : ""
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0
            onLoaded: item.cardVisible = false
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            Text {
                id: githubLink
                text: qsTr("Found an issue? Report it on GitHub")
                color: root.linkColor
                font.pixelSize: 12
                font.weight: Font.DemiBold
                wrapMode: Text.NoWrap

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(App.Constants.repoUrl)
                }
            }

            Rectangle {
                visible: diagnosticsLoader.active
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                color: Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.2)
            }

            Label {
                visible: diagnosticsLoader.active
                text: diagnosticsLoader.item
                      ? diagnosticsLoader.item.diagnoseState.summary
                            || qsTr("Checking required dependencies...")
                      : qsTr("Checking required dependencies...")
                color: diagnosticsLoader.item
                       ? diagnosticsLoader.item.colorForKind(
                             diagnosticsLoader.item.diagnoseState.summaryKind)
                       : palette.text
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.maximumWidth: 280
            }

            Button {
                visible: diagnosticsLoader.active
                text: qsTr("View Diagnostics")
                flat: true
                onClicked: diagnosticsLoader.item.openDiagnostics()
            }
        }

        Item { Layout.preferredHeight: 6 }
    }
}
