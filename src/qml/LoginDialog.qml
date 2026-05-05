import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import com.kdab.cxx_qt.demo 1.0

Dialog {
    id: dialog
    readonly property Apps apps: Apps {}
    title: "Login to App Store - iDescriptor"
    modal: true
    standardButtons: Dialog.NoButton
    anchors.centerIn: parent

    Connections {
        target : apps
        function onStateChanged() {

        }
    }

    property bool loading: false
    property string errorText: ""

    contentItem: ColumnLayout {
        spacing: 12
        // padding: 16

        Label { text: "Email:"; font.pixelSize: 14 }
        TextField {
            id: emailField
            placeholderText: "Enter your email"
            enabled: !dialog.loading
            Layout.fillWidth: true
        }

        Label { text: "Password:"; font.pixelSize: 14 }
        TextField {
            id: passwordField
            placeholderText: "Enter your password"
            echoMode: TextInput.Password
            enabled: !dialog.loading
            Layout.fillWidth: true
        }

        Label {
            text: "You shouldn't be using your main account here and don't worry, your credentials won't be stored or shared anywhere. This App is open-source."
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        BusyIndicator {
            running: dialog.loading
            visible: dialog.loading
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: dialog.errorText
            color: "#c00"
            visible: dialog.errorText.length > 0
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Button {
                text: "Cancel"
                enabled: !dialog.loading
                onClicked: dialog.reject()
            }

            Button {
                text: "Sign In"
                enabled: !dialog.loading
                onClicked: {
                    if (!emailField.text || !passwordField.text) {
                        dialog.errorText = "Email and password cannot be empty."
                        return
                    }
                    dialog.loading = true
                    dialog.errorText = ""
                    apps.login
                    // FIXME: implement
                    apps.login(emailField.text, passwordField.text);

                    dialog.loading = false
                }
            }
        }
    }
}
