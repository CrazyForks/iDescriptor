pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.impl
import "." as App

Item {
    id: root

    property int currentSection: 0
    property string title: ""
    property string udid: ""
    required property string iconPath
    property bool expanded: true
    readonly property bool selectedDevice: App.DeviceContext.currentTab === 0
                                           && udid.length > 0
                                           && App.DeviceContext.currentDeviceUdid === udid
    property real animationProgress: expanded ? 1 : 0
    readonly property string displayTitle: title && title.length ? title : qsTr("Unknown device")
    required property bool wireless

    signal sectionChanged(int sectionIndex)

    implicitWidth: 175
    implicitHeight: card.implicitHeight

    Behavior on animationProgress {
        NumberAnimation {
            duration: App.Theme.mediumAnimation
            easing.type: Easing.OutCubic
        }
    }

    ListModel {
        id: navModel
        ListElement {
            name: qsTr("Info")
            sectionIndex: 0
            iconSource: "qrc:/resources/icons/sidebar_info.svg"
        }
        ListElement {
            name: qsTr("Apps")
            sectionIndex: 1
            iconSource: "qrc:/resources/icons/sidebar_apps.svg"
        }
        ListElement {
            name: qsTr("Gallery")
            sectionIndex: 2
            iconSource: "qrc:/resources/icons/sidebar_gallery.svg"
        }
        ListElement {
            name: qsTr("Files")
            sectionIndex: 3
            iconSource: "qrc:/resources/icons/sidebar_files.svg"
        }
    }

    function selectDevice() {
        App.DeviceContext.selectConnectedDevice(root.udid);
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
        onTapped: function (point) {
            contextMenu.x = point.position.x;
            contextMenu.y = point.position.y;
            contextMenu.open();
        }
    }

    Rectangle {
        id: card
        width: root.width
        implicitHeight: contentColumn.implicitHeight + 8
        radius: App.Theme.sidebarCornerRadius
        color: "transparent"

        ColumnLayout {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            spacing: 2

            Item {
                id: header
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(34, headerRow.implicitHeight)

                HoverHandler {
                    id: headerHover
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.selectDevice()
                }

                Rectangle {
                    anchors.fill: parent
                    radius: App.Theme.sidebarCornerRadius - 2
                    color: root.selectedDevice ? root.expanded ? "transparent" : App.Theme.selectionSoft
                                               : headerHover.hovered ? App.Theme.hover
                                                                     : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: App.Theme.fastAnimation
                        }
                    }
                }

                RowLayout {
                    id: headerRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 3
                    anchors.rightMargin: 3
                    spacing: 6

                    Image {
                        source: root.iconPath
                        sourceSize.width: 26
                        sourceSize.height: 26
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.displayTitle
                        color: App.Theme.text
                        // font.weight: root.selectedDevice ? Font.DemiBold : Font.Normal
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    IconImage {
                        visible: root.wireless
                        source: "qrc:/resources/icons/qlementine-icons_wireless-1-16.svg"
                        color: App.Theme.icon
                        sourceSize.width: 15
                        sourceSize.height: 15
                        Layout.preferredWidth: 15
                        Layout.preferredHeight: 15
                    }

                    Button {
                        id: toggleButton
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 24
                        hoverEnabled: true
                        flat: true
                        onClicked: root.expanded = !root.expanded

                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: root.expanded ? qsTr("Hide sections") : qsTr("Show sections")

                        background: Rectangle {
                            radius: 4
                            color: toggleButton.down ? App.Theme.pressed
                                                     : toggleButton.hovered ? App.Theme.hover
                                                                            : "transparent"
                        }

                        contentItem: IconImage {
                            source: "qrc:/resources/icons/material-symbols_keyboard-arrow-down.svg"
                            color: App.Theme.icon
                            sourceSize.width: 15
                            sourceSize.height: 15
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

            Item {
                id: optionsClip
                Layout.fillWidth: true
                Layout.preferredHeight: (optionsColumn.implicitHeight + 4) * root.animationProgress
                clip: true
                opacity: root.animationProgress
                visible: root.animationProgress > 0.01

                ColumnLayout {
                    id: optionsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    //anchors.leftMargin: 25
                    anchors.rightMargin: 2
                    anchors.topMargin: 2
                    spacing: 2

                    Repeater {
                        model: navModel

                        delegate: Button {
                            id: navButton
                            required property string name
                            required property int sectionIndex
                            required property string iconSource

                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            Layout.maximumHeight: 30
                            text: name
                            checkable: false
                            checked: root.selectedDevice && root.currentSection === sectionIndex
                            hoverEnabled: true
                            leftPadding: 8
                            rightPadding: 8
                            topPadding: 0
                            bottomPadding: 0
                            onClicked: {
                                root.selectDevice();
                                root.sectionChanged(sectionIndex);
                            }

                            background: Rectangle {
                                radius: App.Theme.sidebarCornerRadius - 2
                                color: navButton.checked ? App.Theme.pressed
                                                         : navButton.down ? App.Theme.pressed
                                                                          : navButton.hovered ? App.Theme.hover
                                                                                              : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: App.Theme.fastAnimation
                                    }
                                }
                            }

                            contentItem: RowLayout {
                                spacing: 7
                                anchors.fill: parent
                                anchors.leftMargin: 35

                                IconImage {
                                    source: navButton.iconSource
                                    color: palette.text
                                    sourceSize.width: 16
                                    sourceSize.height: 16
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: navButton.text
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                    color: navButton.checked ? App.Theme.selection
                                                             : App.Theme.text
                                    font.pixelSize: 12
                                    // font.weight: navButton.checked ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
