import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import ".."

FluExpander {
    id: root
    property int currentSection : 1 
    required property string udid
    required property string title 
    required property string iconPath
    property int item_height: 30
    required property bool wireless
    readonly property string displayTitle: title && title.length ? title : qsTr("Unknown device")
    signal sectionChanged(int sectionIndex)

    ListModel {
        id: nav_model
        ListElement { name: qsTr("Info"); sectionIndex: 0 }
        ListElement { name: qsTr("Apps"); sectionIndex: 1 }
        ListElement { name: qsTr("Gallery"); sectionIndex: 2 }
        ListElement { name: qsTr("Files"); sectionIndex: 3 }
    }

    implicitWidth: 175
    contentHeight : root.item_height * 4 + 40

    headerDelegate: Component {
        Item {
            RowLayout {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                spacing: 6

                Image {
                    source: root.iconPath
                    sourceSize.width: 24
                    sourceSize.height: 24
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

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
    }

    content: Item {
        anchors.fill: parent

        
        ListView {
            id: nav_list
            anchors.fill: parent
            anchors.margins : 10
            clip: true
            spacing : 5

            model: nav_model
            interactive: false
            boundsBehavior: ListView.StopAtBounds
            currentIndex : root.currentSection
            highlightMoveDuration: FluTheme.animationEnabled ? 167 : 0
            highlight: Item{
                z:99
                clip: true
                Rectangle{
                    height: 15
                    radius: 1.5
                    color: FluTheme.primaryColor
                    width: 3
                    anchors{
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        leftMargin: 1
                    }
                }
            }
            delegate: FluButton {
                text: name
                width: nav_list.width
                height: root.item_height
                // verticalPadding: 5
                // horizontalPadding:20
                background : Rectangle {
                    color : {
                        if (nav_list.currentIndex == index) {
                            return FluTheme.itemCheckColor
                        }
                        if (hovered) {
                            return FluTheme.itemHoverColor
                        }

                        return "transparent"
                    }
                    radius : 4

                }
                onClicked : {
                    nav_list.currentIndex = index
                    root.sectionChanged(sectionIndex)
                }
            }
        }
    }
}
