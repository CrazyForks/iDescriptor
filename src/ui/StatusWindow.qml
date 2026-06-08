pragma Singleton
import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts

Window {
    id: window
    ListModel { id : processesList } 

    width: 300
    height: 300
    visible: false

    flags: Qt.ToolTip
         | Qt.FramelessWindowHint
         | Qt.WindowStaysOnTopHint

    color: "transparent"

    Component.onCompleted : {
        // TODO: remove
        processesList.append({
            "processId": "test-process-001",
            "title": "Exporting Project Files",
            "type": "Export",
            "status": "Running",
            "currentFile": "Copying: /documents/report.pdf",
            "totalBytes": 10485760,
            "transferredBytes": 5242880,
            "totalItems": 42,
            "completedItems": 23,
            "failedItems": 2,
            "destinationPath": "/Users/username/Downloads/Exports",
            "onComplete": null
        })
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#333"

        ColumnLayout {
            anchors.fill: parent
            Repeater {
                model : processesList
                delegate : Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 250
                    StatusWindowProcess {
                        anchors.fill: parent
                        title: model.title
                        type: model.type
                        status: model.status
                        currentFile: model.currentFile
                        totalBytes: model.totalBytes
                        transferredBytes: model.transferredBytes
                        totalItems: model.totalItems
                        completedItems: model.completedItems
                        failedItems: model.failedItems
                        destinationPath: model.destinationPath
                        onComplete: model.onComplete
                        processId: model.processId
                    }
                }
            }
        }

    }

    function toggle(parentWindow, globalPos) {
        if (window.visible) {
            window.hide()
            return
        }

        var targetX = globalPos.x - (window.width / 2)
        var targetY = globalPos.y - window.height


        transientParent = parentWindow

        window.show() 
        
        window.x = targetX
        window.y = targetY

        window.raise()
    }
}