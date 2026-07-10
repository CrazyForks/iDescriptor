import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import iDescriptor
import "." as App
import "./base"

Item {
    id: root
    required property Query query
    property bool loading: true
    required property var udid 
    required property var albumId 
    property int mediaFilter: 0
    property bool mostRecentFirst: true
    property int selectedFileCount: 0
    property var pendingExportPaths: []
    property string pendingExportTitle: ""

    signal goBack()


    onAlbumIdChanged: {
        console.log("loading album contents")
        if (albumId === undefined || albumId === null) return
        albumContentsModel.clear()
        selectedFileCount = 0
        query.query_album(albumId, mediaFilter, mostRecentFirst)
    }

    onMediaFilterChanged: {
        if (albumId === undefined || albumId === null) return
        albumContentsModel.clear()
        selectedFileCount = 0
        query.query_album(albumId, mediaFilter, mostRecentFirst)
    }

    onMostRecentFirstChanged: {
        if (albumId === undefined || albumId === null) return
        albumContentsModel.clear()
        selectedFileCount = 0
        query.query_album(albumId, mediaFilter, mostRecentFirst)
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
        updateSelectedFileCount()
    }

    function updateSelectedFileCount() {
        let count = 0
        for (let i = 0; i < albumContentsModel.count; i++) {
            if (albumContentsModel.get(i).selected)
                count += 1
        }
        root.selectedFileCount = count
    }

    function selectedFilePaths() {
        const paths = []
        for (let i = 0; i < albumContentsModel.count; i++) {
            const item = albumContentsModel.get(i)
            if (item.selected)
                paths.push(item.filePath)
        }
        return paths
    }

    function currentFilePaths() {
        const paths = []
        for (let i = 0; i < albumContentsModel.count; i++)
            paths.push(albumContentsModel.get(i).filePath)
        return paths
    }

    function chooseExportDestination(paths, title) {
        if (!paths || paths.length === 0)
            return

        root.pendingExportPaths = paths
        root.pendingExportTitle = title
        exportDialog.open()
    }

    function startExport(destinationDir) {
        const paths = root.pendingExportPaths
        if (!paths || paths.length === 0)
            return

        const jobId = QmlUtils.generate_uuid()
        const title = root.pendingExportTitle || qsTr("Exporting Files")
        App.StatusWindow.addProcess(jobId, title, "Export", paths.length, destinationDir)
        ioManager.start_export(root.udid, jobId, paths, destinationDir)
        root.pendingExportPaths = []
        root.pendingExportTitle = ""
    }

    Connections {
        target: query

        function onAlbumQueried(id, mediaFilter, mostRecentFirst, items) {
            if (id !== albumId || mediaFilter !== root.mediaFilter || mostRecentFirst !== root.mostRecentFirst || !items) return
            albumContentsModel.clear()
            root.selectedFileCount = 0

            for (const item of items) {
                albumContentsModel.append({
                    fileName : item,
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

    StateView {
        anchors.fill: parent
        autoSwitchContent: false
        viewState: query.albums.length ? StateView.State.Content : StateView.State.Loading
        contentItem : ColumnLayout {
            anchors.fill : parent

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: qsTr("BACK")
                    enabled : nav.depth > 1
                    onClicked : root.goBack()
                }        

                Item { Layout.fillWidth: true }

                ComboBox {
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { value: 0, label: qsTr("All") },
                        { value: 1, label: qsTr("Images") },
                        { value: 2, label: qsTr("Videos") }
                    ]
                    currentIndex: Math.max(0, indexOfValue(root.mediaFilter))
                    onActivated: root.mediaFilter = currentValue
                }

                ComboBox {
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { value: true, label: qsTr("Most Recent") },
                        { value: false, label: qsTr("Oldest First") }
                    ]
                    currentIndex: Math.max(0, indexOfValue(root.mostRecentFirst))
                    onActivated: root.mostRecentFirst = currentValue
                }
                    
                Button {
                    text: qsTr("Export Selected")
                    enabled: root.selectedFileCount > 0
                    onClicked: root.chooseExportDestination(root.selectedFilePaths(), qsTr("Exporting Selected Files"))
                }

                Button {
                    text: qsTr("Export All")
                    enabled: albumContentsModel.count > 0
                    onClicked: root.chooseExportDestination(root.currentFilePaths(), qsTr("Exporting Files"))
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
                    model: albumContentsModel
                    ScrollBar.vertical: ScrollBar {
                        id: galleryScrollBar
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: ItemDelegate {
                        width: 250
                        height: 250
                        highlighted: selected
                        background: Rectangle {
                            color: "transparent"
                        }
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
                            sourceSize.width: 240 * Screen.devicePixelRatio
                            sourceSize.height: 240 * Screen.devicePixelRatio
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
    }

    FolderDialog {
        id: exportDialog
        title: qsTr("Choose Export Folder")
        onAccepted: root.startExport(QmlUtils.url_to_path(selectedFolder))
    }
}
