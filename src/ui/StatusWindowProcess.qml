import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

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
    
    // Internal state
    property int lastBytesTransferred: 0
    property var lastUpdateTime: new Date()
    property string lastSpeedTex
    property bool isHovered: false
    property bool isRemoveButtonHovered: false
    
    // Timer for throttling speed updates
    Timer {
        id: speedUpdateTimer
        interval: 750
        repeat: false
    }
    
    // Timer for auto-executing onComplete
    Timer {
        id: completeTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.onComplete && typeof root.onComplete === "function") {
                root.onComplete()
            }
        }
    }
    
    width: parent ? parent.width : 300
    height: implicitHeight
    radius: 5
    // color: isDarkMode() ? "rgba(255, 255, 255, 16)" : "rgba(0, 0, 0, 10)"
    color: "transparent"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 5
        
        // Title Row
        RowLayout {
            spacing: 0
            
            Text {
                id: titleText
                text: root.title
                font.bold: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.pointSize: 12
            }
            
            Item { Layout.fillWidth: true }
            
            // Remove Button
            Button {
                // id: myButton
                icon.source: "qrc:/resources/icons/material-symbols_close-rounded.svg"
                // background: Rectangle {
                //     color: "transparent"
                // }
                // width: 24
                // height: 24
                opacity: (root.isHovered && 
                         (root.status === "Completed" || 
                          root.status === "Failed" || 
                          root.status === "Cancelled")) ? 1.0 : 0.0
                
                Behavior on opacity { NumberAnimation { duration: 150 } }
                
                onClicked: {
                    console.log("Remove process:", root.processId)
                    //FIXME
                    // StatusBalloon.removeProcess(root.processId)
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
                color: "#3498db"  // COLOR_ACCENT_BLUE
                
                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }
        
        // Current File Label
        Text {
            text: root.currentFile
            wrapMode: Text.WordWrap
            font.pointSize: 10
            color: "#666"
            Layout.fillWidth: true
            visible: text !== ""
        }
        
        // Stats Label
        Text {
            id: statsLabel
            font.pointSize: 9
            color: "#888"
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
                    if (root.destinationPath !== "") {
                        Qt.openUrlExternally("file:///" + root.destinationPath)
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
                    // IOManagerClient.cancel(root.processId)
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
        
        Item { Layout.fillHeight: true }
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
            completeTimer.start()
        }
    }
    
    Component.onCompleted: {
        console.log("Process item:", root.processItem)
        root.lastUpdateTime = new Date()
        updateStats()
    }
    
    // Hover handling
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.isHovered = true
        onExited: root.isHovered = false
    }
}