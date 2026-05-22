import QtQuick
import QtQuick.Controls
import QtQuick.Layouts 

Item {
    id: root

    enum State {
        Loading,
        Error,
        Content
    }

    property int    viewState:      StateView.State.Loading
    property string errorText:      "Something went wrong."
    property bool   retryable:      true
    property alias  contentItem:    contentSlot.data

    signal retryRequested()

    StackLayout {
        anchors.fill: parent
        currentIndex: root.viewState

        /* 0 — Loading */
        Item {
            BusyIndicator {
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

                Button {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.retryable 
                    text: "Retry"
                    onClicked: root.retryRequested()
                }
            }
        }

        /* 2- Content */
        Item {
            id: contentSlot
        }
    }
}