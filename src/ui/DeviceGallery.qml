import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import iDescriptor
import "." as App
import "./base"

Item {
    id: root

    property var query
    property bool loading: true
    required property var udid
    property int albumId
    required property var info
    readonly property bool isMainPage: nav.depth <= 1
    property int selectedAlbumCount: 0
    property var albumExportSelection: []
    property var is_init: false
    property var pendingAlbumExportRequests: ({})


    Component.onCompleted: {
        console.log("DeviceGallery.qml: Component.onCompleted")
        query = serviceFactory.create_sqlite_query_backend(root.udid, info.ios_version_major)
        if (query) {
            query.init(settingsManager.use_sqlite_gallery_backend());
        } else {
            // FIXME:show error
            console.error("Query is null after create_sqlite_query_backend")
        }
    }

    ListModel {
        id: albumModel
    }

    function openAlbum(id) {
        root.albumId = id
        nav.push(albumContentsComponent, {
            albumId: id,
        })
    }

    function goBack() {
        if (nav.depth > 1) {
            nav.pop()
            // wtf ? do we still depend on albumId after pop 
            root.albumId = 0
        }
    }

    function updateSelectedAlbumCount() {
        let count = 0
        for (let i = 0; i < albumModel.count; i++) {
            if (albumModel.get(i).selected)
                count += 1
        }
        root.selectedAlbumCount = count
    }

    function chooseAlbumExportDestination(albums) {
        if (!albums || albums.length === 0)
            return

        root.albumExportSelection = albums
        albumExportDialog.open()
    }

    function startAlbumExports(destinationRoot) {
        const albums = root.albumExportSelection
        if (!albums || albums.length === 0)
            return

        for (let i = 0; i < albums.length; i++) {
            const album = albums[i]
            const requestId = QmlUtils.generate_uuid()
            const albumName = album.fileName || qsTr("Album")
            const destinationDir = QmlUtils.join_path(destinationRoot, QmlUtils.safe_path_segment(albumName))
            root.pendingAlbumExportRequests[requestId] = {
                albumId: album.albumId,
                albumName: albumName,
                destinationDir: destinationDir
            }
            query.resolve_album_export(requestId, album.albumId, albumName)
        }

        root.albumExportSelection = []
    }

    Connections {
        target: query

        function onStateChanged() {
            if (query.state.init && !root.is_init) {
                root.is_init = true
                query.read_albums()
            }
        }

        function onAlbumsChanged() {
            console.log(JSON.stringify(query.albums))
            albumModel.clear()
            root.selectedAlbumCount = 0

            query.albums.forEach((jsonStr) => {
                const obj = JSON.parse(jsonStr)

                albumModel.append({
                    albumId : obj.album_id ?  obj.album_id : -99,
                    fileName: obj.album_name,
                    filePath: obj.file_path,
                    dateTime: new Date(),
                    selected: false,
                    thumbVersion: 0
                })
            })
        }

        function onAlbumExportResolved(requestId, albumId, albumName, items) {
            const pending = root.pendingAlbumExportRequests[requestId]
            if (!pending)
                return

            delete root.pendingAlbumExportRequests[requestId]
            if (!items || items.length === 0)
                return

            App.StatusWindow.addProcess(
                requestId,
                qsTr("Exporting %1").arg(albumName),
                "Export",
                items.length,
                pending.destinationDir
            )
            ioManager.start_export(root.udid, requestId, items, pending.destinationDir)
        }
    }

    Connections {
        target : imageLoader

        function onThumbnailReady(path, rowHint) {
            const item = albumModel.get(rowHint)
            if (item && item.filePath == path) {
                albumModel.setProperty(rowHint, "thumbVersion", item.thumbVersion + 1)
            }
        }
    }

    StateView {
        anchors.fill: parent
        autoSwitchContent: false
        // viewState: query.albums.length ? StateView.State.Content : StateView.State.Loading
        viewState: query.state.init ? StateView.State.Content : query.state.err ? StateView.State.Error : StateView.State.Loading 
        errorText: query.state.err ? query.state.err : ""
        contentItem : ColumnLayout {
            anchors.fill : parent
            StackView {
                id: nav
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialItem: mainPageComponent
                clip: true

                pushEnter: Transition {
                    PropertyAnimation { property: "x"; from: nav.width; to: 0; duration: 320; easing.type: Easing.OutCubic }
                }
                pushExit: Transition {
                    PropertyAnimation { property: "x"; from: 0; to: -nav.width; duration: 320; easing.type: Easing.OutCubic }
                    PropertyAnimation { property: "opacity"; from: 1; to: 0.55; duration: 320; easing.type: Easing.OutCubic }
                }
                popEnter: Transition {
                    PropertyAnimation { property: "x"; from: -nav.width; to: 0; duration: 280; easing.type: Easing.OutCubic }
                    PropertyAnimation { property: "opacity"; from: 0.55; to: 1; duration: 280; easing.type: Easing.OutCubic }
                }
                popExit: Transition {
                    PropertyAnimation { property: "x"; from: 0; to: nav.width; duration: 280; easing.type: Easing.OutCubic }
                }
            }

        }
    }

    Component {
        id: mainPageComponent

        Item {
            id: albumListPage

            function selectItemsInRect(rect, append) {
                for (let i = 0; i < gallery.count; i++) {
                    const item = gallery.itemAtIndex(i)
                    if (!item) continue

                    const itemRect = {
                        x: item.x,
                        y: item.y - gallery.contentY,
                        w: item.width,
                        h: item.height
                    }

                    const intersects =
                        itemRect.x < rect.x + rect.width &&
                        itemRect.x + itemRect.w > rect.x &&
                        itemRect.y < rect.y + rect.height &&
                        itemRect.y + itemRect.h > rect.y

                    if (intersects) {
                        albumModel.setProperty(i, "selected", true)
                    } else if (!append) {
                        albumModel.setProperty(i, "selected", false)
                    }
                }
                root.updateSelectedAlbumCount()
            }

            function albumAt(index) {
                const row = albumModel.get(index)
                return {
                    albumId: row.albumId,
                    fileName: row.fileName
                }
            }

            function selectedAlbums() {
                const albums = []
                for (let i = 0; i < albumModel.count; i++) {
                    if (albumModel.get(i).selected)
                        albums.push(albumAt(i))
                }
                return albums
            }

            function allAlbums() {
                const albums = []
                for (let i = 0; i < albumModel.count; i++)
                    albums.push(albumAt(i))
                return albums
            }

            ColumnLayout {
                anchors.fill: parent

                RowLayout {
                    Layout.fillWidth: true

                    Button {
                        text: qsTr("Import")
                        // TODO: onClicked
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: qsTr("Export Selected")
                        enabled: root.selectedAlbumCount > 0
                        onClicked: root.chooseAlbumExportDestination(albumListPage.selectedAlbums())
                    }

                    Button {
                        text: qsTr("Export All")
                        enabled: albumModel.count > 0
                        // TODO: Ask the community whether Export All should include duplicate assets from overlapping albums such as Recents/Favorites. For now we export every album folder as-is without duplicate checks.
                        onClicked: root.chooseAlbumExportDestination(albumListPage.allAlbums())
                    }
                }

                Item {
                    id: galleryPane
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    GridView {
                        id: gallery
                        anchors.fill: parent
                        cellWidth: 250
                        cellHeight: 250

                        clip: true
                        model: albumModel
                        ScrollBar.vertical: ScrollBar {
                            id: galleryScrollBar
                            policy: ScrollBar.AsNeeded
                        }
                        delegate: ItemDelegate {
                            width: 240
                            height: 240
                            highlighted: selected
                            background: Rectangle {
                                color: "transparent"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onDoubleClicked: {
                                    console.log("delegate double-click", index, albumId)
                                    root.openAlbum(albumId)
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: selected ? "#4FC3F7" : "transparent"
                                opacity : 0.3
                                z : 1
                            }

                            Image {
                                cache: false
                                anchors.fill: parent
                                //FIXME:use encodeuricomp
                                source: "image://thumb/" + filePath + "?udid=" + root.udid + "&index=" + index + "&v=" + thumbVersion
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: 240 * Screen.devicePixelRatio
                                sourceSize.height: 240 * Screen.devicePixelRatio
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                // text: fileName + albumId
                                text: fileName
                                font.pixelSize: 10
                                color: "white"
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    //rubber band
                    Item {
                        anchors.fill: parent
                        anchors.rightMargin: galleryScrollBar.visible ? galleryScrollBar.width : 0

                        Rectangle {
                            id: selectionRect
                            color: "transparent"
                            border.color: "blue"
                            border.width: 1
                            visible: false

                            opacity: 0.3
                            Rectangle { anchors.fill: parent; color: "blue"; opacity: 0.2 }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            property point startPos

                            propagateComposedEvents: true

                            onPressed: (mouse) => {
                                // mouse.accepted = false
                                startPos = Qt.point(mouse.x, mouse.y)
                                selectionRect.x = startPos.x
                                selectionRect.y = startPos.y
                                selectionRect.width = 0
                                selectionRect.height = 0
                                selectionRect.visible = true
                            }

                            onPositionChanged: {
                                selectionRect.x = Math.min(mouse.x, startPos.x)
                                selectionRect.y = Math.min(mouse.y, startPos.y)
                                selectionRect.width = Math.abs(mouse.x - startPos.x)
                                selectionRect.height = Math.abs(mouse.y - startPos.y)
                            }

                            onReleased: {
                                selectionRect.visible = false

                                const append = mouse.modifiers & Qt.ControlModifier

                                albumListPage.selectItemsInRect({
                                    x: selectionRect.x,
                                    y: selectionRect.y,
                                    width: selectionRect.width,
                                    height: selectionRect.height
                                }, append)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: albumContentsComponent

        AlbumContents {
            query : root.query
            udid : root.udid
            onGoBack : root.goBack()
        }
    }

    FolderDialog {
        id: albumExportDialog
        title: qsTr("Choose Export Folder")
        onAccepted: root.startAlbumExports(QmlUtils.url_to_path(selectedFolder))
    }
}
