import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import "../"


Rectangle {    
    id: section
    property string title : ""
    property int padding: 13
    default property alias content: body.data
    property alias overlay: overlayLayer.data
    readonly property bool hasTitle: title.length > 0
    implicitWidth: sectionLayout.implicitWidth + (section.padding * 2)
    implicitHeight: sectionLayout.implicitHeight + (section.padding * 2)
    color: Theme.softBg
    border.color: Theme.softBgBorder
    border.width: 1
    radius: 10
    ColumnLayout {
        id: sectionLayout
        anchors.fill: parent
        anchors.margins: section.padding
        spacing: 10

        Label {
            Layout.fillWidth: true
            text: section.title
            font.pixelSize: 15
            font.bold: true
            visible: section.hasTitle
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: 8
        }
    }

    Item {
        id: overlayLayer
        anchors.fill: parent
        z: 1
    }
}
