import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import iDescriptor
import "./base"

Item {
    id: root

    property var query
    property bool loading: true
    required property var udid
    property int albumId
    required property var info
    readonly property bool isMainPage: nav.depth <= 1


    Component.onCompleted: {
        query = serviceFactory.create_sqlite_query_backend(root.udid, info.ios_version_major)
        if (query) {
            query.init();
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
        nav.push(albumContentsComponent, { albumId: id })
    }

    function goBack() {
        if (nav.depth > 1) {
            nav.pop()
            root.albumId = 0
        }
    }

    Connections {
        target: query

        function onStateChanged() {
            console.log("state changed")
            query.read_albums()
        }

        function onAlbumsChanged() {
            console.log(JSON.stringify(query.albums))
            albumModel.clear()

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
        viewState: query.albums.length ? StateView.State.Content : StateView.State.Loading
        contentItem : ColumnLayout {
            anchors.fill : parent

            Button {
                text: isMainPage ? qsTr("BACK") : qsTr("BACK TO MAIN")
                enabled : nav.depth > 1
                onClicked : root.goBack()
            }

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

        ScrollView {
            Item {
                id: albumListPage
                width: parent.width
                height: parent.height

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
                }

                GridView {
                    id: gallery
                    anchors.fill: parent
                    cellWidth: 250
                    cellHeight: 250
                    model: albumModel
                    ScrollBar.vertical: ScrollBar {}
                    delegate: ItemDelegate {
                        width: 250
                        height: 250
                        highlighted: selected

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

    Component {
        id: albumContentsComponent

        AlbumContents {
            query : root.query
            udid : root.udid
        }
    }
}
