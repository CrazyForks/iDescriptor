import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import "../"


Rectangle {    
    id: section
    property string title : ""
    default property alias content: body.data
    readonly property bool hasTitle: title.length > 0
    implicitHeight: section.hasTitle ? sectionLayout.implicitHeight + 26 : sectionLayout.implicitHeight
    color: Theme.softBg
    border.color: Theme.softBgBorder
    border.width: 1
    radius: 10
    ColumnLayout {
        id: sectionLayout
        anchors.fill: parent
        anchors.margins: 13
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
}