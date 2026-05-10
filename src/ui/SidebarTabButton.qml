import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id:root
    signal sectionChanged(int sectionIndex) 

    Button {
        Layout.preferredWidth: 220
        Layout.fillHeight: true 
        contentItem : Text {
            text: "Info"
            color: "Red"
        }
        background : Rectangle {
            color : "transparent"
        }
        onClicked: {
            root.sectionChanged(0)
        }
    }

    Button {
        Layout.preferredWidth: 220
        Layout.fillHeight: true
        contentItem : Text {
            text: "Apps"
            color: "Red"
        }
        background : Rectangle {
            color : "transparent"
        }
        onClicked: {
            root.sectionChanged(1)
        }
    }

    Button {
        Layout.preferredWidth: 220
        Layout.fillHeight: true
        contentItem : Text {
            text: "Gallery"
            color: "Red"
        }
        background : Rectangle {
            color : "transparent"
        }
        onClicked: {
            root.sectionChanged(2)
        }
    }

    Button {
        Layout.preferredWidth: 220
        Layout.fillHeight: true
        contentItem : Text {
            text: "Files"
            color: "Red"
        }
        background : Rectangle {
            color : "transparent"
        }
        onClicked: {
            root.sectionChanged(3)
        }
    }

}