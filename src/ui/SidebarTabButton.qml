import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import FluentUI


FluExpander {
    id: root
    property int currentSection : 1
    signal sectionChanged(int sectionIndex)

    ListModel {
        id: nav_model
        ListElement { name: qsTr("Info"); sectionIndex: 0 }
        ListElement { name: qsTr("Apps"); sectionIndex: 1 }
        ListElement { name: qsTr("Gallery"); sectionIndex: 2 }
        ListElement { name: qsTr("Files"); sectionIndex: 3 }
    }

    implicitWidth: 200
    contentHeight : 40 * 4 + 40

    headerDelegate: Component {
        Item {
            FluToggleButton {
                anchors.centerIn: parent
                text: qsTr("TODO")
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
                    height: 18
                    radius: 1.5
                    color: FluTheme.primaryColor
                    width: 3
                    anchors{
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        leftMargin: 6
                    }
                }
            }
            delegate: FluButton {
                text: name
                width: nav_list.width
                height: 40
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
