// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Dialogs
import QtQuick.Layouts
import QtMultimedia
import iDescriptor
import "../base"
import ".." as App

ToolWindow {
    id: root
    width: 760
    height: 620
    minimumWidth: 620
    minimumHeight: 520
    title: qsTr("Wireless Gallery Import - iDescriptor")
    auto_close: false

    readonly property var compatibleExtensions: [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic",
        "heif", "mp4", "mov", "avi", "mkv", "m4v", "3gp", "webm"
    ]

    function fileName(path) {
        const normalized = path.replace(/\\/g, "/")
        return normalized.substring(normalized.lastIndexOf("/") + 1)
    }

    function isGalleryCompatible(path) {
        const dot = path.lastIndexOf(".")
        if (dot < 0)
            return false
        const ext = path.substring(dot + 1).toLowerCase()
        return compatibleExtensions.indexOf(ext) !== -1
    }

    function containsPath(path) {
        for (let i = 0; i < selectedFilesModel.count; ++i) {
            if (selectedFilesModel.get(i).path === path)
                return true
        }
        return false
    }

    function addFiles(files, replaceExisting) {
        if (replaceExisting)
            selectedFilesModel.clear()

        for (let i = 0; i < files.length; ++i) {
            const path = QmlUtils.url_to_path(files[i])
            if (path.length > 0 && isGalleryCompatible(path) && !containsPath(path)) {
                selectedFilesModel.append({
                    path: path,
                    name: fileName(path)
                })
            }
        }
    }

    function selectedPaths() {
        const paths = []
        for (let i = 0; i < selectedFilesModel.count; ++i)
            paths.push(selectedFilesModel.get(i).path)
        return paths
    }

    onClosing: WebWirelessGalleryImport.stop()

    component Card: Rectangle {
        radius: 14
        color: App.Theme.groupedBackground
        border.color: App.Theme.softBgBorder
        border.width: 1
    }

    component PrimaryButton: Button {
        id: control
        leftPadding: 18
        rightPadding: 18
        topPadding: 11
        bottomPadding: 11
        font.weight: Font.DemiBold

        contentItem: Text {
            text: control.text
            color: App.Theme.textSelected
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 10
            color: !control.enabled
                   ? Qt.rgba(App.Theme.accent.r, App.Theme.accent.g, App.Theme.accent.b, 0.42)
                   : control.down ? App.Theme.accentPressed
                                  : control.hovered ? App.Theme.accentHover
                                                    : App.Theme.accent
        }
    }

    component SecondaryButton: Button {
        id: control
        leftPadding: 14
        rightPadding: 14
        topPadding: 9
        bottomPadding: 9

        contentItem: Text {
            text: control.text
            color: control.enabled ? App.Theme.text : App.Theme.textMuted
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 10
            color: control.down ? App.Theme.pressed
                                : control.hovered ? App.Theme.hover
                                                  : App.Theme.controlFill
            border.color: App.Theme.controlStroke
            border.width: 1
        }
    }

    ListModel {
        id: selectedFilesModel
    }

    FileDialog {
        id: fileDialog
        title: qsTr("Select Photos and Videos")
        fileMode: FileDialog.OpenFiles
        nameFilters: [
            qsTr("Media Files (*.jpg *.jpeg *.png *.gif *.bmp *.tiff *.tif *.webp *.heic *.heif *.mp4 *.mov *.avi *.mkv *.m4v *.3gp *.webm)"),
            qsTr("All Files (*)")
        ]
        onAccepted: root.addFiles(selectedFiles, true)
    }

    Dialog {
        id: importDialog
        modal: true
        focus: true
        width: Math.min(root.width - 40, 680)
        height: Math.min(root.height - 40, 590)
        anchors.centerIn: parent
        title: qsTr("Import to Photos")
        standardButtons: Dialog.Cancel
        onRejected: WebWirelessGalleryImport.stop()

        property bool showVideo: false
        property string progressText: qsTr("Download progress will appear here")
        property int qrCodePixelSize: 0
        readonly property var instructionSteps: [
            qsTr("Scan the QR code with your iPhone or iPad."),
            qsTr("On the web page, tap Copy Server Address."),
            qsTr("Install the shortcut once, then tap Run Shortcut."),
            qsTr("Allow the shortcut to save the selected items to Photos.")
        ]

        background: Rectangle {
            radius: 16
            color: App.Theme.windowBackground
        }

        contentItem: ColumnLayout {
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 10
                    color: App.Theme.selectionSoft

                    IconImage {
                        anchors.centerIn: parent
                        width: 21
                        height: 21
                        source: "qrc:/resources/icons/qlementine-icons_wireless-1-16.svg"
                        color: App.Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Ready to share %1 item(s)").arg(selectedFilesModel.count)
                        color: App.Theme.text
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Keep this window open while the shortcut downloads your files.")
                        color: App.Theme.textMuted
                        wrapMode: Text.WordWrap
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                Card {
                    Layout.preferredWidth: 232
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 204
                            Layout.preferredHeight: 204
                            radius: 12
                            color: App.Theme.controlFill
                            border.color: App.Theme.controlStroke
                            border.width: 1

                            QmlImage {
                                id: qrCodeImage
                                anchors.centerIn: parent
                                width: importDialog.qrCodePixelSize
                                height: importDialog.qrCodePixelSize
                                visible: WebWirelessGalleryImport.state.qrCodeReady === true
                            }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 32
                                spacing: 8
                                visible: WebWirelessGalleryImport.state.qrCodeReady !== true

                                BusyIndicator {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    running: WebWirelessGalleryImport.state.error.length === 0
                                }

                                Label {
                                    width: parent.width
                                    text: WebWirelessGalleryImport.state.error.length > 0
                                          ? qsTr("Unable to create QR code")
                                          : qsTr("Preparing QR code…")
                                    color: WebWirelessGalleryImport.state.error.length > 0
                                           ? App.Theme.systemRed
                                           : App.Theme.textMuted
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: WebWirelessGalleryImport.state.serverAddress.length > 0
                                  ? qsTr("Server: %1").arg(WebWirelessGalleryImport.state.serverAddress)
                                  : qsTr("Starting local server…")
                            color: App.Theme.textMuted
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                text: importDialog.showVideo ? qsTr("Video Guide") : qsTr("On your device")
                                color: App.Theme.text
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                            }

                            SecondaryButton {
                                text: importDialog.showVideo ? qsTr("Show Steps") : qsTr("Watch Video")
                                onClicked: {
                                    importDialog.showVideo = !importDialog.showVideo
                                    if (importDialog.showVideo)
                                        instructionVideo.play()
                                    else
                                        instructionVideo.stop()
                                }
                            }
                        }

                        StackLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            currentIndex: importDialog.showVideo ? 1 : 0

                            ColumnLayout {
                                spacing: 12

                                Repeater {
                                    model: importDialog.instructionSteps

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            Layout.preferredWidth: 26
                                            Layout.preferredHeight: 26
                                            radius: 13
                                            color: App.Theme.selectionSoft

                                            Label {
                                                anchors.centerIn: parent
                                                text: index + 1
                                                color: App.Theme.accent
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: modelData
                                            color: App.Theme.text
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }

                            Video {
                                id: instructionVideo
                                fillMode: VideoOutput.PreserveAspectFit
                                source: "qrc:/resources/wireless-gallery-import.mp4"
                                loops: MediaPlayer.Infinite
                                onVisibleChanged: visible ? play() : stop()
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: statusColumn.implicitHeight + 20
                radius: 10
                color: WebWirelessGalleryImport.state.error.length > 0
                       ? Qt.rgba(App.Theme.systemRed.r, App.Theme.systemRed.g, App.Theme.systemRed.b, App.Theme.darkMode ? 0.16 : 0.10)
                       : App.Theme.softBg
                border.color: WebWirelessGalleryImport.state.error.length > 0
                              ? App.Theme.systemRed
                              : App.Theme.controlStroke

                ColumnLayout {
                    id: statusColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 10
                    spacing: 3

                    Label {
                        Layout.fillWidth: true
                        text: WebWirelessGalleryImport.state.error.length > 0
                              ? WebWirelessGalleryImport.state.error
                              : importDialog.progressText
                        color: WebWirelessGalleryImport.state.error.length > 0
                               ? App.Theme.systemRed
                               : App.Theme.text
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: WebWirelessGalleryImport.state.importUrl.length > 0
                        text: WebWirelessGalleryImport.state.importUrl
                        color: App.Theme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                    }
                }
            }
        }
    }

    Connections {
        target: WebWirelessGalleryImport

        function onQrCodeReady(data, pixelSize) {
            importDialog.qrCodePixelSize = pixelSize
            qrCodeImage.set_frame(data)
        }

        function onDownload_progress(fileName, bytesDownloaded, totalBytes) {
            // TODO: bring in a progress bar each item
            importDialog.progressText = qsTr("Downloaded: %1 (%2 KB of %3 KB)")
                .arg(fileName)
                .arg(Math.floor(bytesDownloaded / 1024))
                .arg(Math.floor(totalBytes / 1024))
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 13
                color: App.Theme.selectionSoft

                IconImage {
                    anchors.centerIn: parent
                    width: 25
                    height: 25
                    source: "qrc:/resources/icons/material-symbols_image-outline-sharp.svg"
                    color: App.Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Import to Photos wirelessly")
                    color: App.Theme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Choose media, then scan a QR code to transfer it with the iDescriptor shortcut.")
                    color: App.Theme.textMuted
                    wrapMode: Text.WordWrap
                }
            }

            SecondaryButton {
                text: qsTr("Choose Files…")
                onClicked: fileDialog.open()
            }
        }

        Card {
            id: fileCard
            Layout.fillWidth: true
            Layout.fillHeight: true
            border.color: fileDropArea.containsDrag ? App.Theme.accent : App.Theme.softBgBorder
            border.width: fileDropArea.containsDrag ? 2 : 1
            color: fileDropArea.containsDrag ? App.Theme.selectionHover : App.Theme.groupedBackground

            Behavior on color {
                ColorAnimation { duration: App.Theme.fastAnimation }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Selected Media")
                        color: App.Theme.text
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        Layout.preferredWidth: countLabel.implicitWidth + 16
                        Layout.preferredHeight: 26
                        radius: 13
                        color: selectedFilesModel.count > 0
                               ? App.Theme.selectionSoft
                               : App.Theme.softBg

                        Label {
                            id: countLabel
                            anchors.centerIn: parent
                            text: selectedFilesModel.count
                            color: selectedFilesModel.count > 0
                                   ? App.Theme.accent
                                   : App.Theme.textMuted
                            font.weight: Font.DemiBold
                        }
                    }

                    Button {
                        id: clearButton
                        visible: selectedFilesModel.count > 0
                        flat: true
                        text: qsTr("Clear")
                        onClicked: selectedFilesModel.clear()

                        contentItem: Text {
                            text: clearButton.text
                            color: clearButton.down ? App.Theme.accentPressed : App.Theme.accent
                            font: clearButton.font
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 8
                            color: clearButton.hovered ? App.Theme.hover : "transparent"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: App.Theme.separator
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 32, 360)
                        spacing: 10
                        visible: selectedFilesModel.count === 0

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 58
                            height: 58
                            radius: 18
                            color: App.Theme.softBg
                            border.color: App.Theme.controlStroke

                            IconImage {
                                anchors.centerIn: parent
                                width: 29
                                height: 29
                                source: "qrc:/resources/icons/material-symbols_image-outline-sharp.svg"
                                color: fileDropArea.containsDrag ? App.Theme.accent : App.Theme.icon
                            }
                        }

                        Label {
                            width: parent.width
                            text: fileDropArea.containsDrag
                                  ? qsTr("Drop to add these files")
                                  : qsTr("Drop photos and videos here")
                            color: App.Theme.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Label {
                            width: parent.width
                            text: qsTr("JPEG, HEIC, PNG, MOV, MP4, and other common media formats")
                            color: App.Theme.textMuted
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    ListView {
                        id: fileListView
                        anchors.fill: parent
                        visible: selectedFilesModel.count > 0
                        model: selectedFilesModel
                        clip: true
                        spacing: 4

                        ScrollBar.vertical: ScrollBar {}

                        delegate: Rectangle {
                            id: fileRow
                            required property int index
                            required property string name
                            required property string path
                            width: fileListView.width
                            height: 48
                            radius: 9
                            color: rowHover.hovered ? App.Theme.hover : App.Theme.rowSurface
                            border.color: rowHover.hovered ? App.Theme.controlStroke : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: App.Theme.fastAnimation }
                            }

                            HoverHandler {
                                id: rowHover
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    radius: 8
                                    color: App.Theme.selectionSoft

                                    IconImage {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        source: "qrc:/resources/icons/material-symbols_image-outline-sharp.svg"
                                        color: App.Theme.accent
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Label {
                                        Layout.fillWidth: true
                                        text: fileRow.name
                                        color: App.Theme.text
                                        elide: Text.ElideMiddle
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: fileRow.path
                                        color: App.Theme.textMuted
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                    }
                                }

                                ToolButton {
                                    id: removeButton
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    icon.source: "qrc:/resources/icons/material-symbols_close-rounded.svg"
                                    icon.color: App.Theme.icon
                                    display: AbstractButton.IconOnly
                                    onClicked: selectedFilesModel.remove(fileRow.index)

                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Remove")

                                    background: Rectangle {
                                        radius: 8
                                        color: removeButton.down ? App.Theme.pressed
                                                                 : removeButton.hovered ? App.Theme.hover
                                                                                        : "transparent"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            DropArea {
                id: fileDropArea
                anchors.fill: parent

                onDropped: function(drop) {
                    if (!drop.hasUrls)
                        return
                    root.addFiles(drop.urls, false)
                    drop.acceptProposedAction()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                Layout.fillWidth: true
                visible: WebWirelessGalleryImport.state.error.length > 0
                text: WebWirelessGalleryImport.state.error
                color: App.Theme.systemRed
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                visible: WebWirelessGalleryImport.state.error.length === 0
                text: selectedFilesModel.count === 0
                      ? qsTr("Add at least one photo or video to continue.")
                      : qsTr("%1 item(s) ready to share").arg(selectedFilesModel.count)
                color: App.Theme.textMuted
                wrapMode: Text.WordWrap
            }

            PrimaryButton {
                text: qsTr("Continue")
                enabled: selectedFilesModel.count > 0
                Layout.preferredWidth: 150
                onClicked: {
                    importDialog.progressText = qsTr("Waiting for downloads…")
                    importDialog.qrCodePixelSize = 0
                    WebWirelessGalleryImport.start(root.selectedPaths())
                    importDialog.open()
                }
            }
        }
    }
}
