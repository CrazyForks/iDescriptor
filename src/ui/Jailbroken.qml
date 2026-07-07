import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent

    property var sshTerminalToolWindow: null

    function openSshTerminalTool() {
        if (sshTerminalToolWindow) {
            sshTerminalToolWindow.show()
            sshTerminalToolWindow.raise()
            sshTerminalToolWindow.requestActivate()
            return
        }

        const comp = Qt.createComponent("./tools/SSHTerminalTool.qml")
        if (comp.status !== Component.Ready) {
            console.error("Failed to load SSHTerminalTool:", comp.errorString())
            return
        }

        const win = comp.createObject(root, {
            udid: "",
            device: null,
            auto_close: false
        })

        if (!win) {
            console.error("Failed to create SSHTerminalTool:", comp.errorString())
            return
        }

        sshTerminalToolWindow = win
        win.closing.connect(function() {
            sshTerminalToolWindow = null
            win.destroy(0)
        })
        win.show()
        win.raise()
        win.requestActivate()
    }

    readonly property var tools: ([
        {
            title: qsTr("SSH Terminal"),
            description: qsTr("Connect to your device via SSH"),
            iconSource: "qrc:/resources/icons/bxs_terminal.svg",
            enabled: true,
            action: "ssh"
        },
        {
            title: qsTr("More Tools Coming"),
            description: qsTr("New features will be added soon"),
            iconSource: "qrc:/resources/icons/icon-park-outline_more-two.svg",
            enabled: false,
            action: ""
        }
    ])

    GridLayout {
        anchors.fill: parent
        anchors.margins: 10
        columns: 3
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: root.tools

            delegate: Rectangle {
                id: tile
                Layout.fillWidth: true
                Layout.preferredHeight: 118
                Layout.alignment: Qt.AlignTop
                radius: 8
                color: mouse.containsMouse && modelData.enabled ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                border.color: mouse.containsMouse && modelData.enabled ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                border.width: 1
                opacity: modelData.enabled ? 1.0 : 0.45

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: modelData.enabled
                    cursorShape: modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (modelData.action === "ssh")
                            root.openSshTerminalTool()
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        source: modelData.iconSource
                        color: "#0a84ff"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.title
                        horizontalAlignment: Text.AlignHCenter
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.description
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                        opacity: 0.72
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
