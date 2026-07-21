import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "./base"
import "." as App

Item {
    id: root

    required property var device
    property string udid: device.udid

    property var afcClient: null
    property var afc2Client: null
    property bool afc2Available: false
    property bool loading: true
    property string errorMessage: ""
    property int currentExplorerIndex: 0
    property string selectedSidebarKey: "default"
    property bool componentReady: false

    readonly property string favoritePlacesPrefix: "favorite_places/"
    readonly property string favoritePlacesAfc2Prefix: "favorite_places_afc2/"

    ListModel {
        id: favoritesModel
    }

    function resetUi() {
        root.loading = true
        root.errorMessage = ""
        root.afcClient = null
        root.afc2Client = null
        root.afc2Available = false
        root.currentExplorerIndex = 0
        root.selectedSidebarKey = "default"
        root.updateState()
    }

    function updateState() {
        if (root.loading) {
            stateView.viewState = StateView.State.Loading
        } else if (root.errorMessage.length > 0) {
            stateView.errorText = root.errorMessage
            stateView.viewState = StateView.State.Error
        } else {
            stateView.viewState = StateView.State.Content
        }
    }

    function loadClients() {
        root.resetUi()

        if (!root.udid.length) {
            root.loading = false
            root.errorMessage = qsTr("No device selected.")
            root.updateState()
            return
        }

        root.afcClient = root.device.afcClient
        if (!root.afcClient) {
            root.loading = false
            root.errorMessage = qsTr("The default file service is unavailable.")
            root.updateState()
            return
        }

        root.afc2Client = serviceFactory.create_afc_client(root.udid, true)
        root.afc2Available = Boolean(root.afc2Client)
        root.loading = false
        root.updateState()
    }

    function loadFavoritePlaces() {
        favoritesModel.clear()

        const defaultFavorites = settingsManager.get_favorite_places(root.favoritePlacesPrefix)
        for (let i = 0; i < defaultFavorites.length; ++i) {
            const favorite = defaultFavorites[i]
            favoritesModel.append({
                alias: favorite.alias,
                path: favorite.path,
                afc2: false
            })
        }

        const afc2Favorites = settingsManager.get_favorite_places(root.favoritePlacesAfc2Prefix)
        for (let j = 0; j < afc2Favorites.length; ++j) {
            const favorite = afc2Favorites[j]
            favoritesModel.append({
                alias: favorite.alias,
                path: favorite.path,
                afc2: true
            })
        }
    }

    function saveFavoritePlace(alias, path, afc2) {
        const prefix = afc2 ? root.favoritePlacesAfc2Prefix : root.favoritePlacesPrefix
        settingsManager.save_favorite_place(path, alias, prefix)
    }

    function removeFavoritePlace(index) {
        if (index < 0 || index >= favoritesModel.count)
            return

        const favorite = favoritesModel.get(index)
        const sidebarKey = "favorite:" + (favorite.afc2 ? "afc2:" : "default:") + favorite.path
        if (root.selectedSidebarKey === sidebarKey)
            root.selectedSidebarKey = favorite.afc2 ? "afc2" : "default"

        const prefix = favorite.afc2 ? root.favoritePlacesAfc2Prefix : root.favoritePlacesPrefix
        settingsManager.remove_favorite_place(prefix, favorite.path)
    }

    function selectExplorer(afc2, path, sidebarKey) {
        if (afc2 && !root.afc2Available)
            return

        root.currentExplorerIndex = afc2 ? 1 : 0
        root.selectedSidebarKey = sidebarKey

        const explorer = afc2 ? explorerAfc2 : explorerDefault
        if (path && path.length > 0)
            explorer.navigateToPath(path)
        else
            explorer.goHome()
    }

    Component.onCompleted: {
        root.componentReady = true
        root.loadFavoritePlaces()
        root.loadClients()
    }

    onUdidChanged: {
        if (root.componentReady)
            root.loadClients()
    }

    Connections {
        target: settingsManager

        function onFavoritePlacesChanged() {
            root.loadFavoritePlaces()
        }
    }

    StateView {
        id: stateView
        anchors.fill: parent
        autoSwitchContent: false
        viewState: StateView.State.Loading
        errorText: qsTr("The file explorer could not be loaded.")
        onRetryRequested: root.loadClients()

        contentItem: SplitView {
            anchors.fill: parent
            orientation: Qt.Horizontal

            handle: Rectangle {
                implicitWidth: 7
                radius:10
                color: SplitHandle.pressed
                    ? App.Theme.focus
                    : SplitHandle.hovered ? App.Theme.selectionStroke : App.Theme.sidebarDivider

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: parent.height
                    color: App.Theme.sidebarDivider
                }
            }

            Item {
                id: sidebar
                SplitView.preferredWidth: 230
                SplitView.minimumWidth: 160
                SplitView.maximumWidth: 320
                SplitView.fillHeight: true
                //color: App.Theme.sidebarBackground

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: Math.max(parent.width, 1)
                        spacing: 4

                        SidebarSectionLabel {
                            text: qsTr("Explorer")
                        }

                        SidebarRow {
                            title: qsTr("Default")
                            iconSource: "qrc:/resources/icons/material-symbols_folder.svg"
                            selected: root.selectedSidebarKey === "default"
                            onActivated: root.selectExplorer(false, "", "default")
                        }

                        SidebarRow {
                            title: qsTr("Jailbroken (AFC2)")
                            subtitle: root.afc2Available ? qsTr("Full filesystem") : qsTr("Unavailable")
                            iconSource: "qrc:/resources/icons/material-symbols_folder.svg"
                            rowEnabled: root.afc2Available
                            selected: root.selectedSidebarKey === "afc2"
                            onActivated: root.selectExplorer(true, "", "afc2")
                        }

                        SidebarSectionLabel {
                            Layout.topMargin: 10
                            text: qsTr("Common Places")
                        }

                        SidebarRow {
                            title: qsTr("Pictures")
                            subtitle: qsTr("/DCIM")
                            iconSource: "qrc:/resources/icons/material-symbols_image-outline-sharp.svg"
                            selected: root.selectedSidebarKey === "pictures"
                            onActivated: root.selectExplorer(false, "/DCIM", "pictures")
                        }

                        SidebarSectionLabel {
                            Layout.topMargin: 10
                            text: qsTr("Favorite Places")
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.rightMargin: 10
                            Layout.preferredHeight: favoritesModel.count === 0 ? implicitHeight : 0
                            visible: favoritesModel.count === 0
                            text: qsTr("No favorite locations yet")
                            color: App.Theme.textMuted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: favoritesModel

                            delegate: SidebarRow {
                                required property int index
                                required property string alias
                                required property string path
                                required property bool afc2

                                title: alias
                                subtitle: afc2 ? qsTr("AFC2 · %1").arg(path) : path
                                iconSource: "qrc:/resources/icons/material-symbols_favorite.svg"
                                rowEnabled: !afc2 || root.afc2Available
                                selected: root.selectedSidebarKey === "favorite:" + (afc2 ? "afc2:" : "default:") + path
                                acceptsRightClick: true

                                onActivated: root.selectExplorer(
                                    afc2,
                                    path,
                                    "favorite:" + (afc2 ? "afc2:" : "default:") + path
                                )
                                onContextRequested: {
                                    favoriteMenu.favoriteIndex = index
                                    favoriteMenu.open()
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }
                    }
                }
            }

            Rectangle {
                SplitView.fillWidth: true
                SplitView.fillHeight: true
                color: App.Theme.controlFill

                StackLayout {
                    anchors.fill: parent
                    currentIndex: root.currentExplorerIndex

                    FileExplorer {
                        id: explorerDefault
                        udid: root.udid
                        afcClient: root.afcClient
                        useAfc2: false
                        favEnabled: true
                        onFavoritePlaceAdded: (alias, path) => root.saveFavoritePlace(alias, path, false)
                    }

                    FileExplorer {
                        id: explorerAfc2
                        udid: root.udid
                        afcClient: root.afc2Client
                        useAfc2: true
                        favEnabled: true
                        onFavoritePlaceAdded: (alias, path) => root.saveFavoritePlace(alias, path, true)
                    }
                }
            }
        }
    }

    Menu {
        id: favoriteMenu
        property int favoriteIndex: -1

        MenuItem {
            text: qsTr("Remove from Favorites")
            onTriggered: root.removeFavoritePlace(favoriteMenu.favoriteIndex)
        }
    }

    component SidebarSectionLabel: Label {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.preferredHeight: 28
        verticalAlignment: Text.AlignVCenter
        color: App.Theme.textMuted
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
    }

    component SidebarRow: Rectangle {
        id: sidebarRow

        property string title: ""
        property string subtitle: ""
        property url iconSource: ""
        property bool selected: false
        property bool rowEnabled: true
        property bool acceptsRightClick: false

        signal activated()
        signal contextRequested()

        Layout.fillWidth: true
        Layout.preferredHeight: subtitle.length > 0 ? 50 : 40
        radius: App.Theme.sidebarCornerRadius
        color: selected
            ? App.Theme.selectionSoft
            : rowHover.hovered && rowEnabled ? App.Theme.hover : "transparent"
        border.color: selected ? App.Theme.selectionStroke : "transparent"
        border.width: 1
        opacity: rowEnabled ? 1 : 0.5

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }

        HoverHandler {
            id: rowHover
        }

        TapHandler {
            acceptedButtons: sidebarRow.acceptsRightClick
                ? Qt.LeftButton | Qt.RightButton
                : Qt.LeftButton
            enabled: sidebarRow.rowEnabled
            onTapped: (eventPoint, button) => {
                if (button === Qt.RightButton)
                    sidebarRow.contextRequested()
                else
                    sidebarRow.activated()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 9

            IconImage {
                source: sidebarRow.iconSource
                sourceSize.width: 19
                sourceSize.height: 19
                Layout.preferredWidth: 19
                Layout.preferredHeight: 19
                color: sidebarRow.selected ? App.Theme.systemBlue : App.Theme.icon
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: sidebarRow.title
                    color: App.Theme.text
                    font.pixelSize: 13
                    font.weight: sidebarRow.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    visible: sidebarRow.subtitle.length > 0
                    text: sidebarRow.subtitle
                    color: App.Theme.textMuted
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }
            }
        }
    }
}
