import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    required property string filePath
    property int thumbVersion: 0
    required property string udid
    property int row : 999999
    id: root
    visible: true   
    width: Screen.width
    height: Screen.height
    visibility: Window.FullScreen
    


    Connections {
        target : ThumbnailProvider

        function onThumbnailReady(path, data, rowHint) {
            if (path == root.filePath && rowHint == root.row) {
                root.thumbVersion++
            }
        }
    }

    Image {
        cache: false
        anchors.fill: parent
        //FIXME:use encodeuricomp
        source: "image://thumb/" + filePath + "?udid=" + root.udid + "&index=" + row + "&v=" + thumbVersion
        fillMode: Image.PreserveAspectFit
    }

}