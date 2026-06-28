import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls.impl

Item {
    id: root
    anchors.fill: parent

    required property string udid
    visible: (parent && parent.currentSection !== undefined) ? (parent.currentSection === 2) : true

    /* clients are created from Rust side */
    property var afcClient: null
    property var afc2Client: null
    property bool afc2Available: false

    property bool loading: true
    property string errorMessage: ""

    /* 0 = default, 1 = afc2 */
    property int currentExplorerIndex: 0

    function _resetUi() {
        loading = true
        errorMessage = ""
        afcClient = null
        afc2Client = null
        afc2Available = false
        currentExplorerIndex = 0
    }

    function loadClients() {
        _resetUi()

        if (!root.udid || root.udid.length === 0) {
            console.log
            loading = false
            console.log("wtf no device")
            errorMessage = qsTr("No device selected.")
            return
        }

        if (typeof serviceFactory === "undefined" || !serviceFactory) {
            loading = false
            errorMessage = qsTr("serviceFactory is not available in QML scope.")
            return
        }

        afcClient = serviceFactory.create_afc_client(root.udid, false)
        afc2Client = serviceFactory.create_afc_client(root.udid, true)

        if (afcClient === null) {
            console.log("No AFC client in FilesSection.qml")
            loading = false
            errorMessage = qsTr("Failed to create AFC client.")
            return
        }
        console.log("AFC client ready")

        afc2Available = (afc2Client !== null)
        loading = false
    }

    Component.onCompleted: loadClients()

    // FIXME: wire up settings )
    ListModel { id: favoritesModel }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            id: sidebar
            Layout.preferredWidth: 250
            Layout.maximumWidth: 250
            Layout.fillHeight: true
            color: "transparent"
            border.color: "#1f000000"
            border.width: 1

            ListView {
                id: sidebarList
                anchors.fill: parent
                clip: true

                model: ListModel {
                    id: sidebarModel

                    ListElement { kind: "header"; title: "Explorer"; icon: "qrc:/resources/icons/material-symbols_folder.svg" }
                    ListElement { kind: "explorer"; title: "Default"; icon: "qrc:/resources/icons/material-symbols_folder.svg"; afc2: false }
                    ListElement { kind: "explorer"; title: "Jailbroken (AFC2)"; icon: "qrc:/resources/icons/material-symbols_folder.svg"; afc2: true }

                    ListElement { kind: "header"; title: "Common Places"; icon: "qrc:/resources/icons/material-symbols_favorite.svg" }
                    ListElement { kind: "place"; title: "Pictures"; icon: "qrc:/resources/icons/material-symbols_folder.svg"; path: "/DCIM"; afc2: false }

                    ListElement { kind: "header"; title: "Favorite Places"; icon: "qrc:/resources/icons/material-symbols_favorite.svg" }
                }

                delegate: Item {
                    id: row
                    width: ListView.view.width
                    height: (model.kind === "header") ? 44 : 40

                    property bool isHeader: model.kind === "header"
                    property bool isExplorer: model.kind === "explorer"
                    property bool isPlace: model.kind === "place"

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        IconImage {
                            source: model.icon
                            Layout.preferredHeight: 34
                            Layout.preferredWidth: 34
                            color: palette.text
                            opacity: 1.0
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr(model.title)
                            font.bold: row.isHeader
                            elide: Text.ElideRight
                            color: palette.text
                        }

                        Text {
                            visible: row.isExplorer && model.afc2 && !root.afc2Available
                            text: qsTr("(unavailable)")
                            color: "#666"
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !row.isHeader && !(row.isExplorer && model.afc2 && !root.afc2Available)
                        onClicked: {
                            if (row.isExplorer) {
                                root.currentExplorerIndex = model.afc2 ? 1 : 0
                                if (root.currentExplorerIndex === 0) explorerDefault.goHome()
                                else explorerAfc2.goHome()
                                return
                            }
                            if (row.isPlace) {
                                root.currentExplorerIndex = model.afc2 ? 1 : 0
                                if (root.currentExplorerIndex === 0) explorerDefault.navigateToPath(model.path)
                                else explorerAfc2.navigateToPath(model.path)
                                return
                            }
                        }
                    }
                }

                footer: Item {
                    width: sidebarList.width
                    height: favCol.implicitHeight

                    Column {
                        id: favCol
                        width: parent.width

                        Repeater {
                            model: favoritesModel

                            delegate: Item {
                                id: favRow
                                width: favCol.width
                                height: 40

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Image {
                                        source: "qrc:/resources/icons/material-symbols_folder.svg"
                                        Layout.preferredHeight: 34
                                        Layout.preferredWidth: 34
                                        // FIXME:theming
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: alias
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: afc2 === true
                                        text: qsTr("AFC2")
                                        color: "#666"
                                        font.pixelSize: 12
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            favMenu._index = index
                                            favMenu.open()
                                            return
                                        }
                                        root.currentExplorerIndex = afc2 ? 1 : 0
                                        if (root.currentExplorerIndex === 0) explorerDefault.navigateToPath(path)
                                        else explorerAfc2.navigateToPath(path)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Menu {
                id: favMenu
                property int _index: -1

                MenuItem {
                    text: qsTr("Remove from Favorites")
                    onTriggered: {
                        if (favMenu._index >= 0) favoritesModel.remove(favMenu._index)
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                id: mainStack
                anchors.fill: parent
                currentIndex: root.loading ? 1 : (root.errorMessage.length > 0 ? 2 : 0)

                // Content
                Item {
                    id: contentView
                    anchors.fill: parent

                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.currentExplorerIndex

                        FileExplorer {
                            id: explorerDefault
                            afcClient: root.afcClient
                            favEnabled: true

                            // onFavoritePlaceAdded: (alias, path) => {
                            //     // FIXME
                            //     favoritesModel.append({ "alias": alias, "path": path, "afc2": false })
                            // }
                        }

                        Item {
                            anchors.fill: parent

                            FileExplorer {
                                id: explorerAfc2
                                anchors.fill: parent
                                afcClient: root.afc2Client
                                favEnabled: true

                                visible: root.afc2Available
                                // onFavoritePlaceAdded: (alias, path) => {
                                //     favoritesModel.append({ "alias": alias, "path": path, "afc2": true })
                                // }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                visible: !root.afc2Available

                                Text { text: qsTr("AFC2 is not available on this device."); color: "#444" }
                                Button {
                                    text: qsTr("Switch to Default")
                                    onClicked: root.currentExplorerIndex = 0
                                }
                            }
                        }
                    }
                }

                // Loading
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    BusyIndicator { running: true }
                    Text { text: qsTr("Loading file explorer..."); color: "#444" }
                }

                // Error
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    width: Math.min(parent.width * 0.8, 520)

                    Text {
                        text: root.errorMessage
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: "#444"
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Button { text: qsTr("Try Again"); onClicked: root.loadClients() }
                    }
                }
            }
        }
    }
}
