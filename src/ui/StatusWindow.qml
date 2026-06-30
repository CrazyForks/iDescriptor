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
        // processesList.append({
        //     "processId": "test-process-001",
        //     "title": "Exporting Project Files",
        //     "type": "Export",
        //     "status": "Running",
        //     "currentFile": "Copying: /documents/report.pdf",
        //     "totalBytes": 10485760,
        //     "transferredBytes": 5242880,
        //     "totalItems": 42,
        //     "completedItems": 23,
        //     "failedItems": 2,
        //     "destinationPath": "/Users/username/Downloads/Exports",
        //     "onComplete": null
        // })
    }

    Connections {
        target: ioManager
        enabled: !!ioManager

        function onFile_transfer_progress(jobId, fileName, bytesTransferred, totalBytes) {
            window.updateProgress(jobId, fileName, bytesTransferred, totalBytes)
        }

        function onExport_item_finished(jobId, fileName, destinationPath, success, bytesTransferred, errorMessage) {
            window.finishItem(jobId, success)
        }

        function onExport_job_finished(jobId, cancelled, successfulItems, failedItems, totalBytes) {
            window.finishProcess(jobId, cancelled, successfulItems, failedItems, totalBytes)
        }

        function onImport_item_finished(jobId, fileName, destinationPath, success, bytesTransferred, errorMessage) {
            window.finishItem(jobId, success)
        }

        function onImport_job_finished(jobId, cancelled, successfulItems, failedItems, totalBytes) {
            window.finishProcess(jobId, cancelled, successfulItems, failedItems, totalBytes)
        }
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
                        onRemoveRequested: (processId) => window.removeProcess(processId)
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

    function findProcessIndex(processId) {
        for (var i = 0; i < processesList.count; i++) {
            if (processesList.get(i).processId === processId)
                return i
        }
        return -1
    }

    function addProcess(processId, title, type, totalItems, destinationPath) {
        if (findProcessIndex(processId) !== -1)
            return

        processesList.append({
            "processId": processId,
            "title": title,
            "type": type,
            "status": "Running",
            "currentFile": "",
            "totalBytes": 0,
            "transferredBytes": 0,
            "totalItems": totalItems,
            "completedItems": 0,
            "failedItems": 0,
            "destinationPath": destinationPath,
            "onComplete": null
        })
        window.show()
        window.raise()
    }

    function removeProcess(processId) {
        const index = findProcessIndex(processId)
        if (index === -1)
            return

        processesList.remove(index)
        if (processesList.count === 0)
            window.hide()
    }

    function updateProgress(processId, fileName, transferredBytes, totalBytes) {
        const index = findProcessIndex(processId)
        if (index === -1)
            return

        processesList.setProperty(index, "currentFile", fileName)
        processesList.setProperty(index, "transferredBytes", transferredBytes)
        processesList.setProperty(index, "totalBytes", totalBytes)
    }

    function finishItem(processId, success) {
        const index = findProcessIndex(processId)
        if (index === -1)
            return

        const item = processesList.get(index)
        if (success)
            processesList.setProperty(index, "completedItems", item.completedItems + 1)
        else
            processesList.setProperty(index, "failedItems", item.failedItems + 1)
    }

    function finishProcess(processId, cancelled, successfulItems, failedItems, totalBytes) {
        const index = findProcessIndex(processId)
        if (index === -1)
            return

        processesList.setProperty(index, "status", cancelled ? "Cancelled" : (failedItems > 0 ? "Failed" : "Completed"))
        processesList.setProperty(index, "completedItems", successfulItems)
        processesList.setProperty(index, "failedItems", failedItems)
        processesList.setProperty(index, "transferredBytes", totalBytes)
        processesList.setProperty(index, "totalBytes", totalBytes)
        processesList.setProperty(index, "currentFile", "")
    }
}
