import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App

Item {
    id: root

    property int currentSection: 0
    property string title: ""
    property string udid: ""
    property bool expanded: true
    readonly property bool selectedDevice: udid.length > 0 && App.DeviceContext.currentDeviceUdid === udid
    property real animationProgress: expanded ? 1 : 0
    readonly property string displayTitle: title && title.length ? title : qsTr("Unknown device")
    required property bool wireless 

    signal sectionChanged(int sectionIndex)

    implicitWidth: 200
    implicitHeight: card.implicitHeight

    Behavior on animationProgress {
        NumberAnimation {
            duration: App.Theme.mediumAnimation
            easing.type: Easing.OutCubic
        }
    }

    ListModel {
        id: navModel
        ListElement { name: qsTr("Info"); sectionIndex: 0 }
        ListElement { name: qsTr("Apps"); sectionIndex: 1 }
        ListElement { name: qsTr("Gallery"); sectionIndex: 2 }
        ListElement { name: qsTr("Files"); sectionIndex: 3 }
    }

    function selectDevice() {
        App.DeviceContext.currentDeviceUdid = root.udid
        App.DeviceContext.currentRecoveryDeviceId = ""
    }

    Menu {
        id: contextMenu

        MenuItem {
            text: qsTr("Remove")
            enabled: root.udid.length > 0
            onTriggered: App.DeviceContext.removeDevice(root.udid)
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: function(point) {
            contextMenu.x = point.position.x
            contextMenu.y = point.position.y
            contextMenu.open()
        }
    }

    Rectangle {
        id: card
        width: root.width
        implicitHeight: contentColumn.implicitHeight + 10
        radius: App.Theme.sidebarCornerRadius
        color: root.selectedDevice ? App.Theme.hover : App.Theme.controlFill
        border.color: root.selectedDevice ? App.Theme.focus : App.Theme.controlStroke
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }

        ColumnLayout {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            spacing: 5

            Item {
                id: header
                Layout.fillWidth: true
                Layout.preferredHeight: headerColumn.implicitHeight

                HoverHandler { id: headerHover }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.selectDevice()
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: headerHover.hovered ? App.Theme.hover : "transparent"
                }

                ColumnLayout {
                    id: headerColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Label {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.displayTitle
                            color: App.Theme.text
                            font.bold: true
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Image {
                            visible: root.wireless
                            source: "qrc:/resources/icons/qlementine-icons_wireless-1-16.svg"
                            sourceSize.width: 16
                            sourceSize.height: 16
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            opacity: 0.8
                        }
                    }

                    Button {
                        id: toggleButton
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        leftPadding: 5
                        rightPadding: 5
                        topPadding: 0
                        bottomPadding: 0
                        flat: true
                        hoverEnabled: true
                        text: root.expanded ? qsTr("Hide sections") : qsTr("Show sections")
                        onClicked: root.expanded = !root.expanded

                        background: Rectangle {
                            radius: 4
                            color: toggleButton.down ? App.Theme.pressed
                                                 : toggleButton.hovered ? App.Theme.hover
                                                                        : "transparent"
                        }

                        contentItem: RowLayout {
                            spacing: 4

                            Label {
                                Layout.fillWidth: true
                                text: toggleButton.text
                                color: App.Theme.textMuted
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            Image {
                                source: "qrc:/resources/icons/material-symbols_keyboard-arrow-down.svg"
                                sourceSize.width: 16
                                sourceSize.height: 16
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                opacity: 0.72
                                rotation: root.expanded ? 0 : -90

                                Behavior on rotation {
                                    NumberAnimation {
                                        duration: App.Theme.mediumAnimation
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: optionsClip
                Layout.fillWidth: true
                Layout.preferredHeight: optionsColumn.implicitHeight * root.animationProgress
                clip: true
                opacity: root.animationProgress
                visible: root.animationProgress > 0.01

                ColumnLayout {
                    id: optionsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    anchors.topMargin: 5
                    spacing: 3

                    Repeater {
                        model: navModel

                        delegate: Button {
                            id: navButton
                            required property string name
                            required property int sectionIndex

                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            text: name
                            checkable: true
                            checked: root.currentSection === sectionIndex
                            hoverEnabled: true
                            onClicked: {
                                root.selectDevice()
                                root.sectionChanged(sectionIndex)
                            }

                            background: Rectangle {
                                radius: 6
                                color: navButton.checked ? App.Theme.selection
                                      : navButton.down ? App.Theme.pressed
                                      : navButton.hovered ? App.Theme.hover
                                                          : App.Theme.controlFill
                                border.color: navButton.checked ? App.Theme.selection
                                            : navButton.hovered ? App.Theme.focus
                                                                : App.Theme.controlStroke
                                border.width: 1

                                Behavior on color {
                                    ColorAnimation { duration: App.Theme.fastAnimation }
                                }

                                Behavior on border.color {
                                    ColorAnimation { duration: App.Theme.fastAnimation }
                                }
                            }

                            contentItem: Label {
                                text: navButton.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: navButton.checked ? App.Theme.textSelected : App.Theme.text
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
