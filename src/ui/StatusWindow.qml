pragma Singleton
import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import "./base"

DefaultWindow {
    id: window
    showMaximize: false
    showMinimize: false
    showClose: false
    ListModel { id : processesList }
    _effect : "normal"
    width: 300
    height: 300
    visible: false
    autoVisible: false
    autoDestroy: false
    fitsAppBarWindows: true
    property var registeredParentWindow: null
    property var registeredOpener: null

    flags: Qt.ToolTip
         | Qt.FramelessWindowHint
         | Qt.WindowStaysOnTopHint

    color: "transparent"

    onVisibleChanged: {
        if (!visible)
            StatusWindowController.uninstall()
    }


    Connections {
        target: ioManager
        enabled: !!ioManager

        function onFileTransferProgress(jobId, fileName, bytesTransferred, totalBytes) {
            window.updateProgress(jobId, fileName, bytesTransferred, totalBytes)
        }

        function onExportItemFinished(jobId, fileName, destinationPath, success, bytesTransferred, errorMessage) {
            window.finishItem(jobId, success)
        }

        function onExportJobFinished(jobId, cancelled, successfulItems, failedItems, totalBytes) {
            window.finishProcess(jobId, cancelled, successfulItems, failedItems, totalBytes)
        }

        //hide process bar when failed
        function onImportItemFinished(jobId, fileName, destinationPath, success, bytesTransferred, errorMessage) {
            window.finishItem(jobId, success)
        }

        function onImportJobFinished(jobId, cancelled, successfulItems, failedItems, totalBytes) {
            window.finishProcess(jobId, cancelled, successfulItems, failedItems, totalBytes)
        }
    }

    Connections {
        target: StatusWindowController

        function onCloseRequested(reason) {
            if (window.visible)
                window.hide()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.platform.os !== "windows" ? palette.window : "transparent"
        border.color: Qt.platform.os !== "windows" ? Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.12) : "transparent"
        border.width: Qt.platform.os !== "windows" ? 1 : 0

        ColumnLayout {
            anchors.fill: parent

            ScrollView {
                id: processesScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: processesScroll.availableWidth
                    height: Math.max(implicitHeight, processesScroll.availableHeight)
                    spacing: 0

                    Repeater {
                        model : processesList
                        delegate : Item {
                            id: processDelegate
                            Layout.fillWidth: true

                            implicitHeight: processItem.implicitHeight
                            Layout.preferredHeight: implicitHeight

                            StatusWindowProcess {
                                id: processItem
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

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }
        }

    }

    Label {
        text: qsTr("Export & Import processes will appear here")
        font.pixelSize: 12
        color: palette.text
        anchors.centerIn: parent
        visible: !processesList.count
    }

    function registerOpener(parentWindow, opener) {
        registeredParentWindow = parentWindow
        registeredOpener = opener
    }

    function unregisterOpener(opener) {
        if (registeredOpener === opener) {
            registeredParentWindow = null
            registeredOpener = null
        }
    }

    function positionForOpener(parentWindow, globalPos, openerWidth, openerHeight) {
        var targetX = globalPos.x + (openerWidth - window.width) / 2
        var targetY = globalPos.y - window.height
        var available = parentWindow && parentWindow.screen
                ? parentWindow.screen.availableGeometry
                : null

        if (available) {
            targetX = Math.max(available.x,
                               Math.min(targetX, available.x + available.width - window.width))

            // The sidebar footer normally has space above it. If the main window is
            // near the top of a screen, place the process window below instead.
            if (targetY < available.y)
                targetY = globalPos.y + openerHeight

            targetY = Math.max(available.y,
                               Math.min(targetY, available.y + available.height - window.height))
        }

        window.x = targetX
        window.y = targetY
    }

    function openForOpener(parentWindow, globalPos, openerWidth, openerHeight) {
        transientParent = parentWindow
        positionForOpener(parentWindow, globalPos, openerWidth, openerHeight)
        window.show()
        window.raise()
        StatusWindowController.install(window, globalPos.x, globalPos.y, openerWidth, openerHeight)
    }

    function openAtRegisteredOpener() {
        if (!registeredParentWindow || !registeredOpener) {
            // This can only happen while the main UI is still being created.
            // Keep the process window usable until the sidebar footer registers.
            window.show()
            window.raise()
            StatusWindowController.install(window, 0, 0, 0, 0)
            return false
        }

        var globalPos = registeredOpener.mapToGlobal(0, 0)
        openForOpener(registeredParentWindow, globalPos,
                      registeredOpener.width, registeredOpener.height)
        return true
    }

    function toggle(parentWindow, globalPos, openerWidth, openerHeight) {
        if (window.visible) {
            window.hide()
            return
        }

        openForOpener(parentWindow, globalPos, openerWidth, openerHeight)
    }

    function findProcessIndex(processId) {
        for (var i = 0; i < processesList.count; i++) {
            if (processesList.get(i).processId === processId)
                return i
        }
        return -1
    }

    function addProcess(processId, title, type, totalItems, destinationPath) {
        console.log(processId, title, type, totalItems, destinationPath)

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
        openAtRegisteredOpener()
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
