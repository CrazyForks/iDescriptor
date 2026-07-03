import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"

Item {
    id: root

    implicitWidth: 520
    implicitHeight: card.implicitHeight

    property var diagnoseState: DiagnoseImpl.state

    function colorForKind(kind) {
        if (kind === "ok")
            return "#16a34a"
        if (kind === "warning")
            return "#d97706"
        if (kind === "error")
            return "#dc2626"
        return "#6b7280"
    }

    function statusText(modelData) {
        if (modelData.availability === 0)
            return qsTr("Installed")
        if (modelData.availability === 1)
            return qsTr("Installed, not running")
        if (modelData.availability === 2)
            return qsTr("Missing")
        return qsTr("Unable to check")
    }

    function actionText(modelData) {
        if (modelData.id === "udev_rules")
            return qsTr("View Instructions")
        if (modelData.availability === 1)
            return qsTr("Start")
        return qsTr("Install")
    }

    function updateStateView() {
        if (diagnoseState.error && diagnoseState.error.length > 0)
            diagnosticsState.viewState = StateView.State.Error
        else if (diagnoseState.checking)
            diagnosticsState.viewState = StateView.State.Loading
        else
            diagnosticsState.viewState = StateView.State.Content
    }

    function scheduleCheck() {
        diagnosticsState.viewState = StateView.State.Loading
        delayedCheckTimer.restart()
    }

    onDiagnoseStateChanged: {
        updateStateView()

        if (diagnoseState.notice && diagnoseState.notice.length > 0)
            noticeDialog.open()
    }

    Component.onCompleted: scheduleCheck()

    Timer {
        id: delayedCheckTimer
        interval: 350
        repeat: false
        onTriggered: DiagnoseImpl.check()
    }

    Dialog {
        id: noticeDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        title: qsTr("Dependency Check")
        standardButtons: Dialog.Ok
        onAccepted: DiagnoseImpl.clear_notice()
        onRejected: DiagnoseImpl.clear_notice()

        Label {
            width: 360
            text: root.diagnoseState.notice || ""
            wrapMode: Text.WordWrap
        }
    }

    Dialog {
        id: diagnosticsDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        title: qsTr("Diagnostics")
        width: 620
        height: 500
        standardButtons: Dialog.Close
        onOpened: root.updateStateView()

        contentItem: StateView {
            id: diagnosticsState
            implicitWidth: 580
            implicitHeight: 390
            autoSwitchContent: false
            retryable: true
            errorText: root.diagnoseState.error || qsTr("Unable to check system dependencies.")
            onRetryRequested: root.scheduleCheck()

            contentItem: SectionBox {
                anchors.fill: parent
                title: qsTr("Dependency Check")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            radius: 6
                            color: root.colorForKind(root.diagnoseState.summaryKind)
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.diagnoseState.summary || qsTr("Checking system dependencies...")
                            color: root.colorForKind(root.diagnoseState.summaryKind)
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Button {
                            text: qsTr("Refresh")
                            enabled: !root.diagnoseState.checking
                            onClicked: root.scheduleCheck()
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        interactive: contentHeight > height
                        model: root.diagnoseState.items || []
                        spacing: 8

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 78
                            radius: 7
                            color: "transparent"
                            border.color: "transparent"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 9
                                    Layout.preferredHeight: 9
                                    radius: 5
                                    color: root.colorForKind(modelData.statusKind)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: "white"
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: modelData.optional
                                            text: qsTr("Optional")
                                            color: "#94a3b8"
                                            font.pixelSize: 11
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.description
                                        color: "#94a3b8"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.statusText(modelData)
                                        color: root.colorForKind(modelData.statusKind)
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                BusyIndicator {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    visible: root.diagnoseState.installingId === modelData.id
                                    running: visible
                                }

                                Button {
                                    visible: modelData.actionVisible && root.diagnoseState.installingId !== modelData.id
                                    enabled: !root.diagnoseState.checking && root.diagnoseState.installingId.length === 0
                                    text: root.actionText(modelData)
                                    onClicked: DiagnoseImpl.install(modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: card
        width: root.implicitWidth
        implicitHeight: 72
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Dependency Check")
                    color: "white"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.diagnoseState.summary || qsTr("Checking system dependencies...")
                    color: root.colorForKind(root.diagnoseState.summaryKind)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Button {
                text: qsTr("View Diagnostics")
                onClicked: diagnosticsDialog.open()
            }
        }
    }
}
