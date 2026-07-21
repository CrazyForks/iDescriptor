import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root

    required property string name
    required property string logo
    required property string website
    required property string tierLabel
    required property color tierColor
    required property bool useBundleIdForIcon
    required property string description
    property string bundleId: ""
    property string iconSource: ""
    color: "transparent"

    signal installRequested(string bundleId, string appName)

    readonly property bool hasWebsite: root.website.trim().length > 0

    implicitWidth: 260
    implicitHeight: 128
    radius: 8

    Component.onCompleted: {
        if (root.logo && !root.useBundleIdForIcon) {
            iconSource = root.logo;
        } else if (root.bundleId) {
            Helpers.fetchAppIconFromApple(root.bundleId, function(url) { iconSource = url; });
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12



        IconLoader {
            anchors.margins: 6
            radius: 0
            iconSource: root.iconSource
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.name
                    color: Theme.text
                    font.pixelSize: 16
                    font.bold: true
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: tierText.implicitWidth + 12
                    Layout.preferredHeight: 20
                    radius: 5
                    color: root.tierColor

                    Label {
                        id: tierText
                        anchors.centerIn: parent
                        text: root.tierLabel + " Sponsor"
                        color: "#262626"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: root.description
                color: Theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true

                Button {
                    visible: root.bundleId.length > 0
                    text: qsTr("Install App")
                    onClicked: root.installRequested(root.bundleId, "")
                }

                Button {
                    Layout.fillWidth: true
                    flat: true
                    visible: root.hasWebsite
                    text: qsTr("Visit website →")

                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: Theme.accent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }

                    onClicked: Qt.openUrlExternally(root.website)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 4
                color: Theme.separator
            }
        }
    }
}
