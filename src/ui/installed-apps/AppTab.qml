import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Button {
    id: root

    required property var device
    required property string appName
    required property string bundleId
    property string version: ""
    required property string iconSource
    property bool selected: false

    signal appClicked(string bundleId)

    width: ListView.view ? ListView.view.width : implicitWidth
    height: 60
    padding: 0
    hoverEnabled: true
    enabled: true
    onClicked: root.appClicked(root.bundleId)

    Component.onCompleted: {
        device.sb_client.fetch_app_icon(root.bundleId)
    }

    background: Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.selected ? palette.highlight : (root.hovered ? Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.1) : Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.06))
        border.width: 1
        border.color: root.selected ? Qt.lighter(palette.highlight, 1.15) : Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.12)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 10

        // Rectangle {
        //     Layout.preferredWidth: 32
        //     Layout.preferredHeight: 32
        //     radius: 7
        //     color: Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.08)
        //     clip: true

        //     IconLoader {
        //         id: iconImg
        //         iconSource: root.iconSource
        //         // visible: root.iconSource.length > 0 && status === Image.Ready
        //     }

        //     // Text {
        //     //     anchors.centerIn: parent
        //     //     text: root.appName.length > 0 ? root.appName.charAt(0).toUpperCase() : qsTr("?")
        //     //     color: root.selected ? palette.highlightedText : palette.text
        //     //     font.bold: true
        //     //     font.pixelSize: 14
        //     //     visible: root.iconSource.length === 0 || iconImg.status !== Image.Ready
        //     // }
        // }

        IconLoader {
            id: iconImg
            iconSource: root.iconSource
            // visible: root.iconSource.length > 0 && status === Image.Ready
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.appName
                color: root.selected ? palette.highlightedText : palette.text
                font.weight: Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: root.version
                color: root.selected ? Qt.rgba(palette.highlightedText.r, palette.highlightedText.g, palette.highlightedText.b, 0.75) : Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.62)
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: root.version.length > 0
            }

        }

    }

}
