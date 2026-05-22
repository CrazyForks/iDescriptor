import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "./base"

Dialog {
    id: dlg
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: parent

    width: 560
    height: 560

    property int currentIndex: 0
    property bool loading: true

    Timer {
        id: loadTimer
        interval: 300
        repeat: false
        onTriggered: stateView.viewState = StateView.State.Content
    }

    function updateNav() {
        prevBtn.enabled = dlg.currentIndex > 0
        nextBtn.enabled = dlg.currentIndex < (stack.count - 1)
    }

    onCurrentIndexChanged: updateNav()
    Component.onCompleted: {
        updateNav()
        loadTimer.start()
    }

    background: Rectangle {
        radius: 10
        color: palette.window
        border.color: Qt.rgba(0, 0, 0, 0.12)
        border.width: 1
    }

    contentItem: StateView {
        id: stateView
        anchors.fill: parent
        viewState: StateView.State.Loading 
        contentItem : ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StackLayout {
                    id: stack
                    anchors.fill: parent
                    currentIndex: dlg.currentIndex

                    // Page 1
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            Item { Layout.fillHeight: true }

                            Text {
                                Layout.fillWidth: true
                                text: "Connect your device"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: 16
                                font.bold: true
                                color: palette.text
                            }

                            Image {
                                Layout.alignment: Qt.AlignHCenter
                                source: "qrc:/resources/connect.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 200
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    // Page 2
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            Item { Layout.fillHeight: true }

                            Text {
                                Layout.fillWidth: true
                                text: "Accept the pairing dialog"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: 16
                                font.bold: true
                                color: palette.text
                            }

                            Image {
                                Layout.alignment: Qt.AlignHCenter
                                source: "qrc:/resources/trust.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 200
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    // Page 3
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            Item { Layout.fillHeight: true }

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (Qt.platform.os === "windows")
                                        return qsTr("You can now unplug the device. iDescriptor will connect to it automatically (requires iOS 15 or later and the Bonjour service).")
                                    if (Qt.platform.os === "linux")
                                        return qsTr("You can now unplug the device. iDescriptor will connect to it automatically (requires iOS 15 or later and the Avahi daemon).")
                                    return qsTr("You can now unplug the device. iDescriptor will connect to it automatically (requires iOS 15 or later).")
                                }
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: 16
                                font.bold: true
                                color: palette.text
                            }

                            Image {
                                Layout.alignment: Qt.AlignHCenter
                                source: "qrc:/resources/ios-version.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 200
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item { Layout.fillWidth: true }

                Button {
                    id: prevBtn
                    icon.source: "qrc:/resources/icons/material-symbols_arrow-left-alt.svg"
                    Layout.preferredWidth: 48
                    onClicked: {
                        if (dlg.currentIndex > 0) dlg.currentIndex -= 1
                    }
                }

                Button {
                    id: nextBtn
                    icon.source: "qrc:/resources/icons/material-symbols_arrow-right-alt.svg"
                    Layout.preferredWidth: 48
                    onClicked: {
                        if (dlg.currentIndex < stack.count - 1) dlg.currentIndex += 1
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}