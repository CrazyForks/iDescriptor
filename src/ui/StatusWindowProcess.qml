import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "./"

Rectangle {
    id: root
    
    required property string title
    required property string status
    required property int totalBytes 
    required property int transferredBytes 
    required property string currentFile
    required property int completedItems 
    required property int totalItems 
    required property int failedItems 
    required property string processId
    required property string type
    required property string destinationPath
    required property var onComplete
    signal removeRequested(string processId)
    property bool  onCompleteRan: false
    
    // Internal state
    property int lastBytesTransferred: 0
    property var lastUpdateTime: new Date()
    property string lastSpeedText: ""
    property bool isHovered: false
    property bool isRemoveButtonHovered: false
    readonly property color primaryTextColor: "#f5f5f5"
    readonly property color secondaryTextColor: "#d0d0d0"
    readonly property color mutedTextColor: "#aaa"
    
    // Timer for throttling speed updates
    Timer {
        id: speedUpdateTimer
        interval: 750
        repeat: false
    }
    
    width: parent ? parent.width : 300
    implicitHeight: content.implicitHeight + 30
    height: implicitHeight
    radius: 5
    color: "transparent"
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 15
        spacing: 5
        
        // Title Row
        RowLayout {
            spacing: 0
            
            Text {
                id: titleText
                text: root.title
                color: root.primaryTextColor
                font.bold: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.pointSize: 12
            }
            
            Item { Layout.fillWidth: true }
            
            Button {
                id: removeButton
                icon.source: "qrc:/resources/icons/material-symbols_close-rounded.svg"
                visible: root.status === "Completed" ||
                         root.status === "Failed" ||
                         root.status === "Cancelled"
                background: Rectangle {
                    color: "transparent"
                }
                opacity: root.isHovered ? 1.0 : 0.0
                enabled: visible && root.isHovered
                
                Behavior on opacity { NumberAnimation { duration: 150 } }
                
                onClicked: {
                    console.log("Remove process:", root.processId)
                    root.removeRequested(root.processId)
                }
            }
        }
        
        // Status Label
        Text {
            id: statusLabel
            text: {
                if (root.status === "Running") {
                    return root.currentFile === "" ? "Starting..." : "Running"
                } else if (root.status === "Completed") return "Completed successfully"
                else if (root.status === "Failed") return "Failed"
                else if (root.status === "Cancelled") return "Cancelled"
                else return ""
            }
            Layout.fillWidth: true
            color: root.secondaryTextColor
            font.pointSize: 11
        }
        
        // Progress Bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 12
            radius: 4
            color: "#eee"
            
            Rectangle {
                width: parent.width * (root.progress / 100)
                height: parent.height
                radius: 4
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }
        
        // Current File Label
        Text {
            text: root.currentFile
            wrapMode: Text.WordWrap
            font.pointSize: 10
            color: root.mutedTextColor
            Layout.fillWidth: true
            visible: text !== ""
        }
        
        // Stats Label
        Text {
            id: statsLabel
            font.pointSize: 9
            color: root.mutedTextColor
            Layout.fillWidth: true
        }
        
        // Buttons Row
        RowLayout {
            spacing: 6
            Layout.topMargin: 5
            
            // Action Button
            Button {
                id: actionButton
                text: root.type === "Export" ? "Open Folder" : ""
                visible: (root.type === "Export" && root.status === "Completed")
                onClicked: {
                        console.log("Open destination folder:", root.destinationPath)
                    if (root.destinationPath !== "") {
                        Qt.openUrlExternally(root.localFileUrl(root.destinationPath))
                    }
                }
                
                background: Rectangle {
                    color: parent.down ? "#d0d0d0" : (parent.hovered ? "#e0e0e0" : "#f0f0f0")
                    border.color: "#c0c0c0"
                    border.width: 1
                    radius: 4
                }
                
                contentItem: Text {
                    text: parent.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: "#333"
                }
            }
            
            Item { Layout.fillWidth: true }
            
            // Cancel Button
            Button {
                id: cancelButton
                text: {
                    if (!enabled) return "Cancelling..."
                    return "Cancel"
                }
                visible: (root.status === "Running")
                enabled: true
                
                onClicked: {
                    cancelButton.enabled = false
                    console.log("Cancel process:", root.processId)
                    if (ioManager)
                        ioManager.cancel_job(root.processId)
                }
                
                background: Rectangle {
                    color: parent.down ? "#d0d0d0" : (parent.hovered ? "#e0e0e0" : "#f0f0f0")
                    border.color: "#c0c0c0"
                    border.width: 1
                    radius: 4
                }
                
                contentItem: Text {
                    text: parent.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: "#333"
                }
            }
        }
    }
    
    // Computed property for progress
    readonly property real progress: {
        if (root.totalBytes > 0 && root.transferredBytes > 0) {
            return (root.transferredBytes * 100) / root.totalBytes
        }
        return 0
    }
    
    // Update stats text and speed calculation
    function updateStats() {
        var stats = root.completedItems + " of " + root.totalItems + " items"
        
        if (root.failedItems > 0) {
            stats += " • " + root.failedItems + " failed"
        }
        
        if (root.status === "Running" && root.transferredBytes > 0) {
            var now = new Date()
            var elapsed = root.lastUpdateTime ? (now - root.lastUpdateTime) : 0
            
            if (!root.lastUpdateTime || elapsed >= 750) {
                if (elapsed > 0) {
                    var bytesDiff = root.transferredBytes - root.lastBytesTransferred
                    var bytesPerSecond = (bytesDiff * 1000) / elapsed
                    if (bytesPerSecond > 0) {
                        root.lastSpeedText = " • " + formatTransferRate(bytesPerSecond)
                    }
                }
                root.lastBytesTransferred = root.transferredBytes
                root.lastUpdateTime = now
            }
            
            if (root.lastSpeedText !== "") {
                stats += root.lastSpeedText
            }
        }
        
        statsLabel.text = stats
    }
    
    // Helper function for formatting transfer rate
    function formatTransferRate(bytesPerSecond) {
        if (bytesPerSecond < 1024) return bytesPerSecond.toFixed(0) + " B/s"
        if (bytesPerSecond < 1024 * 1024) return (bytesPerSecond / 1024).toFixed(1) + " KB/s"
        if (bytesPerSecond < 1024 * 1024 * 1024) return (bytesPerSecond / (1024 * 1024)).toFixed(1) + " MB/s"
        return (bytesPerSecond / (1024 * 1024 * 1024)).toFixed(1) + " GB/s"
    }

    function localFileUrl(path) {
        var normalized = String(path).replace(/\\/g, "/")
        if (normalized.indexOf("file://") === 0)
            return normalized
        if (normalized[0] === "/")
            return "file://" + normalized
        return "file:///" + normalized
    }
    
    // Dark mode detection
    function isDarkMode() {
        // You can implement this based on your theme system
        // This is a placeholder - adapt to your theme detection
        return false
    }
    
    // Update UI when properties change
    onTransferredBytesChanged: updateStats()
    onCompletedItemsChanged: updateStats()
    onFailedItemsChanged: updateStats()
    onStatusChanged: {
        updateStats()
        
        // Handle completion callback
        if (root.status === "Completed") {
            if (root.onComplete && typeof root.onComplete === "function" && !root.onCompleteRan) {
                root.onCompleteRan = true
                root.onComplete()
            }
        }
    }
    
    Component.onCompleted: {
        root.lastUpdateTime = new Date()
        updateStats()
    }
    
    // Hover handling
    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }
}
