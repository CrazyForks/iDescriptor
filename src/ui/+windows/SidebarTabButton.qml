import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import QtQuick.Window
import FluentUI
import ".."

Item {
    id: root

    property int currentSection: 1
    required property string udid
    required property string title
    required property string iconPath
    property int item_height: 30
    required property bool wireless
    property int headerHeight: 45
    property bool expand: false
    readonly property int contentHeight: root.item_height * 4 + 40
    property bool acrylic: settingsManager.window_effect() === "acrylic"
    readonly property bool selectedDevice: root.udid.length > 0 && DeviceContext.currentDeviceUdid === root.udid
    readonly property string displayTitle: title && title.length ? title : qsTr("Unknown device")

    signal sectionChanged(int sectionIndex)

    implicitHeight: Math.max(headerLayout.height + containerLayout.height, headerLayout.height)
    implicitWidth: 175
    clip: true

    function selectDevice() {
        DeviceContext.selectConnectedDevice(root.udid)
    }

    Connections {
        target: Settings

        function onWindow_effectChanged() {
            root.acrylic = Settings.window_effect === "acrylic"
        }

        function onWindowEffectChanged(effect) {
            root.acrylic = effect === "acrylic"
        }
    }

    QtObject {
        id: expanderState

        property bool animateToggle: false

        function toggle() {
            animateToggle = true
            root.expand = !root.expand
            animateToggle = false
        }
    }

    ListModel {
        id: navModel

        ListElement { name: qsTr("Info"); sectionIndex: 0 }
        ListElement { name: qsTr("Apps"); sectionIndex: 1 }
        ListElement { name: qsTr("Gallery"); sectionIndex: 2 }
        ListElement { name: qsTr("Files"); sectionIndex: 3 }
    }

    Rectangle {
        id: headerLayout

        width: parent.width
        height: root.headerHeight
        radius: 4
        border.color: root.selectedDevice
                      ? Theme.focus
                      : (root.acrylic ? Theme.softBgBorder : FluTheme.dividerColor)
        border.width: 1
        color: root.acrylic
               ? Theme.acrylicSurface
               : (Window.active ? FluTheme.frameActiveColor : FluTheme.frameColor)

        MouseArea {
            id: headerMouse

            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.selectDevice()
        }

        Item {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: toggleButton.left

            RowLayout {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                spacing: 6

                Label {
                    Layout.fillWidth: true
                    font.bold: true
                    text: root.displayTitle
                    elide: Text.ElideRight
                }

            }


            Menu {
                id: contextMenu

                MenuItem {
                    text: qsTr("Remove")
                    enabled: root.udid.length > 0
                    onTriggered: DeviceContext.removeDevice(root.udid)
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
        }

        IconImage {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.top: parent.top
            // anchors.verticalCenter: parent.verticalCenter
            visible: root.wireless
            enabled: false
            z: toggleButton.z + 1
            source: "qrc:/resources/icons/qlementine-icons_wireless-1-16.svg"
            color: palette.text
            sourceSize.width: 14
            sourceSize.height: 14
            width: 14
            height: 14
        }

        FluIconButton {
            id: toggleButton

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 15
            color: {
                if (pressed)
                    return Theme.pressed
                if (headerMouse.containsMouse || hovered)
                    return Theme.hover
                return "transparent"
            }
            onClicked: expanderState.toggle()

            contentItem: FluIcon {
                rotation: root.expand ? 0 : 180
                iconSource: FluentIcons.ChevronUp
                iconSize: 15

                Behavior on rotation {
                    enabled: FluTheme.animationEnabled
                    NumberAnimation {
                        duration: 167
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Item {
        id: containerLayout

        anchors.top: headerLayout.bottom
        anchors.topMargin: -1
        anchors.left: headerLayout.left
        visible: root.contentHeight + container.anchors.topMargin !== 0
        height: root.contentHeight + container.anchors.topMargin
        width: parent.width
        z: -999
        clip: true

        Rectangle {
            id: container

            anchors.fill: parent
            anchors.topMargin: -root.contentHeight
            radius: 4
            clip: true
            color: root.acrylic
                   ? Theme.acrylicSurface
                   : (Window.active ? FluTheme.frameActiveColor : FluTheme.frameColor)
            border.color: root.acrylic ? Theme.softBgBorder : FluTheme.dividerColor

            ListView {
                id: navList

                anchors.fill: parent
                anchors.margins: 10
                clip: true
                spacing: 5
                model: navModel
                interactive: false
                boundsBehavior: ListView.StopAtBounds
                currentIndex: root.currentSection
                highlightMoveDuration: FluTheme.animationEnabled ? 167 : 0

                highlight: Item {
                    z: 99
                    clip: true

                    Rectangle {
                        height: 15
                        radius: 1.5
                        color: FluTheme.primaryColor
                        width: 3
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 1
                    }
                }

                delegate: FluButton {
                    required property int index
                    required property string name
                    required property int sectionIndex

                    text: name
                    width: navList.width
                    height: root.item_height
                    // verticalPadding: 5
                    // horizontalPadding: 20
                    background: Rectangle {
                        color: {
                            if (navList.currentIndex === index)
                                return root.acrylic
                                        ? Theme.selectionSoft
                                        : FluTheme.itemCheckColor
                            if (hovered)
                                return root.acrylic
                                        ? Theme.hover
                                        : FluTheme.itemHoverColor
                            return "transparent"
                        }
                        radius: 4
                    }
                    onClicked: {
                        navList.currentIndex = index
                        root.sectionChanged(sectionIndex)
                    }
                }
            }

            states: [
                State {
                    name: "expanded"
                    when: root.expand
                    PropertyChanges {
                        target: container
                        anchors.topMargin: 0
                    }
                },
                State {
                    name: "collapsed"
                    when: !root.expand
                    PropertyChanges {
                        target: container
                        anchors.topMargin: -root.contentHeight
                    }
                }
            ]

            transitions: [
                Transition {
                    to: "expanded"
                    NumberAnimation {
                        properties: "anchors.topMargin"
                        duration: FluTheme.animationEnabled && expanderState.animateToggle ? 167 : 0
                        easing.type: Easing.OutCubic
                    }
                },
                Transition {
                    to: "collapsed"
                    NumberAnimation {
                        properties: "anchors.topMargin"
                        duration: FluTheme.animationEnabled && expanderState.animateToggle ? 167 : 0
                        easing.type: Easing.OutCubic
                    }
                }
            ]
        }
    }
}
