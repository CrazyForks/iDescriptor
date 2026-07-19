import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./"

Item {
    id: root

    enum State {
        Loading,
        Error,
        Content
    }

    property int    viewState:      StateView.State.Loading
    property int requestedViewState: StateView.State.Loading
    property string errorText:      qsTr("Something went wrong.")
    property bool   retryable:      true
    property bool cancelable: false
    property string retryText: qsTr("Retry")
    property string cancelText: qsTr("Cancel")
    property bool  autoSwitchContent: true
    property int  autoSwitchDelay: 500
    property alias  contentItem:    contentSlot.data
    
    signal retryRequested()
    signal cancelRequested()


    Timer {
        id: autoSwitchTimer
        interval: root.autoSwitchDelay
        repeat: false
        running: root.autoSwitchContent && root.viewState === StateView.State.Loading

        onTriggered: root.viewState = StateView.State.Content
    }

    // Handles switching with spinner
    onRequestedViewStateChanged: {
        if (root.requestedViewState === StateView.State.Content) {
            root.viewState = StateView.State.Loading
            return autoSwitchTimer.start()
        }  
        root.viewState = root.requestedViewState
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: root.viewState

        /* 0 — Loading */
        Item {
            Spinner {
                anchors.centerIn: parent
                running: root.viewState === StateView.State.Loading
            }
        }

        /* 1 — Error */
        Item {
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    Layout.alignment:  Qt.AlignHCenter
                    Layout.maximumWidth: 300
                    text: root.errorText
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "#cc3333"
                    font.pixelSize: 14
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.retryable || root.cancelable
                    spacing: 8

                    Button {
                        visible: root.cancelable
                        text: root.cancelText
                        onClicked: root.cancelRequested()
                    }

                    Button {
                        visible: root.retryable
                        text: root.retryText
                        onClicked: root.retryRequested()
                    }
                }
            }
        }

        /* 2- Content */
        Item {
            id: contentSlot
        }
    }
}
