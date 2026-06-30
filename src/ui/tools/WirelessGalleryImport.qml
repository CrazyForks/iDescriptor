import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtMultimedia
import "../base"
import "../+windows"


ToolWindow {
    id: root
    width: 720
    height: 560
    title: qsTr("Wireless Gallery Import - iDescriptor")
    auto_close: false

    readonly property var compatibleExtensions: [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic",
        "heif", "mp4", "mov", "avi", "mkv", "m4v", "3gp", "webm"
    ]

    function localPath(url) {
        let text = url.toString()
        if (text.startsWith("file://"))
            text = decodeURIComponent(text.substring(7))
        return text
    }

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

    function selectedPaths() {
        const paths = []
        for (let i = 0; i < selectedFilesModel.count; ++i)
            paths.push(selectedFilesModel.get(i).path)
        return paths
    }

    function updateFiles(files) {
        selectedFilesModel.clear()
        for (let i = 0; i < files.length; ++i) {
            const path = localPath(files[i])
            if (isGalleryCompatible(path)) {
                selectedFilesModel.append({
                    path: path,
                    name: fileName(path)
                })
            }
        }
    }

    onClosing: WebWirelessGalleryImport.stop()

    ListModel {
        id: selectedFilesModel
    }

    FileDialog {
        id: fileDialog
        title: qsTr("Select Photos/Videos to Import")
        fileMode: FileDialog.OpenFiles
        nameFilters: [
            qsTr("Media Files (*.jpg *.jpeg *.png *.gif *.bmp *.tiff *.tif *.webp *.heic *.heif *.mp4 *.mov *.avi *.mkv *.m4v *.3gp *.webm)"),
            qsTr("All Files (*)")
        ]
        onAccepted: root.updateFiles(selectedFiles)
    }

    Dialog {
        id: importDialog
        modal: true
        focus: true
        width: Math.min(root.width - 40, 640)
        height: Math.min(root.height - 40, 620)
        anchors.centerIn: parent
        title: qsTr("Import Photos to iDevice - iDescriptor")
        standardButtons: Dialog.Cancel
        onRejected: WebWirelessGalleryImport.stop()

        property bool showVideo: false
        property string progressText: qsTr("Download progress will appear here")

        contentItem: ColumnLayout {
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: qsTr("Files to be served (%1 items):").arg(selectedFilesModel.count)
                font.bold: true
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                clip: true
                model: selectedFilesModel
                delegate: Label {
                    width: ListView.view.width
                    text: model.name
                    elide: Text.ElideMiddle
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 220
                    Layout.alignment: Qt.AlignTop
                    color: palette.base
                    border.color: Qt.rgba(0, 0, 0, 0.18)
                    radius: 6

                    Image {
                        anchors.fill: parent
                        anchors.margins: 10
                        fillMode: Image.PreserveAspectFit
                        // FIXME: call from C++ or Rust to generate QR code instead of using a third-party service
                        source: WebWirelessGalleryImport.state.importUrl
                                ? "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=" + encodeURIComponent(WebWirelessGalleryImport.state.importUrl)
                                : ""
                    }

                    Label {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        visible: !WebWirelessGalleryImport.state.importUrl
                        text: qsTr("QR Code will appear here after starting server")
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: importDialog.showVideo ? 1 : 0

                        ScrollView {
                            TextArea {
                                readOnly: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Instructions on How to Import\n\n1. Scan the QR code to open the web interface\n2. Click on \"Copy Server Address\"\n3. Click on \"Import and Run Shortcut\" if you have not installed the shortcut before or \"Run Shortcut\" if you have installed it before.\n4. Run the shortcut in the Shortcuts app. Once the shortcut imports to your device, it will automatically run \"Photos app\"\n\nSwitch to video tutorial if you want to see a video tutorial.")
                            }
                        }

                        Video {
                            id: instructionVideo
                            fillMode: VideoOutput.PreserveAspectFit
                            source: "qrc:/resources/wireless-gallery-import.mp4"
                            loops: MediaPlayer.Infinite
                            onVisibleChanged: visible ? play() : stop()
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        text: importDialog.showVideo ? qsTr("Show Text Instructions") : qsTr("Show Video Instructions")
                        onClicked: {
                            importDialog.showVideo = !importDialog.showVideo
                            if (importDialog.showVideo)
                                instructionVideo.play()
                            else
                                instructionVideo.stop()
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: importDialog.progressText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                visible: WebWirelessGalleryImport.state.serverAddress
                text: qsTr("Server started at %1").arg(WebWirelessGalleryImport.state.serverAddress)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            TextArea {
                Layout.fillWidth: true
                Layout.preferredHeight: 68
                visible: WebWirelessGalleryImport.state.importUrl
                readOnly: true
                wrapMode: Text.WrapAnywhere
                text: WebWirelessGalleryImport.state.importUrl || ""
            }
        }
    }

    Connections {
        target: WebWirelessGalleryImport
        function onDownload_progress(fileName, bytesDownloaded, totalBytes) {
            // TODO: bring in a progress bar each item
            importDialog.progressText = qsTr("Downloaded: %1 (%2 KB)").arg(fileName).arg(Math.floor(bytesDownloaded / 1024))
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Button {
            text: qsTr("Select Files")
            onClicked: fileDialog.open()
        }

        Label {
            Layout.fillWidth: true
            text: selectedFilesModel.count === 0
                  ? qsTr("No files selected")
                  : qsTr("Selected %1 file(s)").arg(selectedFilesModel.count)
            wrapMode: Text.WordWrap
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: fileListView
                model: selectedFilesModel
                clip: true

                delegate: Rectangle {
                    width: fileListView.width
                    implicitHeight: Math.max(44, fileRow.implicitHeight + 10)
                    color: "transparent"

                    RowLayout {
                        id: fileRow
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            text: model.name
                            wrapMode: Text.WrapAnywhere
                        }

                        Button {
                            text: qsTr("Remove")
                            Layout.maximumWidth: 90
                            onClicked: selectedFilesModel.remove(index)
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: WebWirelessGalleryImport.state.error
            color: "red"
            text: WebWirelessGalleryImport.state.error || ""
            wrapMode: Text.WordWrap
        }

        Button {
            Layout.fillWidth: true
            text: qsTr("Import to Gallery")
            enabled: selectedFilesModel.count > 0
            onClicked: {
                importDialog.progressText = qsTr("Waiting for downloads...")
                WebWirelessGalleryImport.start(root.selectedPaths())
                importDialog.open()
            }
        }
    }
}
