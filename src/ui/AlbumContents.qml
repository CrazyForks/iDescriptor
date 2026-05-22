import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import iDescriptor 1.0


Item {
    id: root
    required property Query query
    property bool loading: true
    required property var udid 
    required property var albumId 


    onAlbumIdChanged: {
        console.log("loading album contents")
        query.query_album(albumId)
    }

    ListModel {
        id: albumContentsModel
    }

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
                albumContentsModel.setProperty(i, "selected", true)
            } else if (!append) {
                albumContentsModel.setProperty(i, "selected", false)
            }
        }
    }

    Connections {
        target: query

        function onAlbum_queried(id, items) {
            if (id !== albumId || !items) return
            albumContentsModel.clear()

            for (const item of items) {
                console.log("item",item)
                albumContentsModel.append({
                    fileName : "wtf",
                    filePath : item,
                    thumbVersion : 0,
                    selected : false
                })
            }

        }
    }

    Connections {
        target : imageLoader

        function onThumbnailReady(path, rowHint) {
            const item = albumContentsModel.get(rowHint)
            if (item && item.filePath == path) {
                albumContentsModel.setProperty(rowHint, "thumbVersion", item.thumbVersion + 1)
            }
        }
    }

    BusyIndicator {
        running: !query.albums
        anchors.centerIn: parent
    }


    GridView {
        id: gallery
        anchors.fill: parent
        interactive: true
        clip: true
        cellWidth: 250
        cellHeight: 250
        acceptedButtons : Qt.NoButton
        model: albumContentsModel

        delegate: ItemDelegate {
            width: 250
            height: 250
            highlighted: selected

            MouseArea {
                anchors.fill: parent
                onDoubleClicked: {
                    const comp = Qt.createComponent("PreviewWindow.qml")

                    if (comp.status === Component.Ready) {
                        const win = comp.createObject(null,{ 
                            filePath,
                            udid : root.udid
                        })
                        if (win !== null) {
                            win.show()
                        } else {
                            console.error("createObject failed:", comp.errorString())
                        }

                    } else if (comp.status === Component.Error) {
                        console.error("Component failed to load:", comp.errorString())
                    }

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
                text: fileName
                font.pixelSize: 10
                color: "white"
                elide: Text.ElideMiddle
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

                    selectItemsInRect({
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
