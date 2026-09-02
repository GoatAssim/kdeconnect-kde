import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kdeconnect

Kirigami.ScrollablePage {
    id: root
    title: i18nd("kdeconnect-app", "Call Bridge")
    property QtObject pluginInterface
    property QtObject device

    property string statusText: ""
    property string callEvent: "idle"
    property string callName: ""
    property string callNumber: ""

    ListModel { id: contactModel }

    Connections {
        target: root.pluginInterface
        function onCallEvent(event, number, contactName, photoBase64) {
            root.callEvent = event
            root.callNumber = number
            root.callName = contactName
            root.statusText = event + " — " + contactName + " " + number
        }
        function onResponseReceived(action, jsonBody, error) {
            if (error && error.length)
                root.statusText = action + " ERROR: " + error
            else
                root.statusText = action + "\n" + jsonBody

            try {
                const obj = JSON.parse(jsonBody)
                if (obj.contacts) {
                    contactModel.clear()
                    for (let i = 0; i < obj.contacts.length; i++) {
                        contactModel.append({
                            roleName: obj.contacts[i].name || "",
                            roleNumber: obj.contacts[i].number || ""
                        })
                    }
                }
            } catch (e) {}
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            text: i18nd("kdeconnect-app", "Controls cellular calls only. Audio stays on the phone (no PC mic/speaker routing).")
            visible: true
        }

        // Active call banner
        QQC2.Frame {
            Layout.fillWidth: true
            visible: root.callEvent === "ringing" || root.callEvent === "talking"
            background: Rectangle {
                color: root.callEvent === "ringing" ? "#3d2a00" : "#1a3320"
                radius: 6
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                QQC2.Label {
                    text: root.callEvent === "ringing" ? i18nd("kdeconnect-app", "Incoming call")
                                                       : i18nd("kdeconnect-app", "On call")
                    font.bold: true
                }
                QQC2.Label { text: root.callName }
                QQC2.Label { text: root.callNumber; opacity: 0.8 }
                RowLayout {
                    QQC2.Button {
                        text: i18nd("kdeconnect-app", "Answer")
                        icon.name: "call-start"
                        visible: root.callEvent === "ringing"
                        onClicked: root.pluginInterface.answer()
                    }
                    QQC2.Button {
                        text: i18nd("kdeconnect-app", "Decline")
                        icon.name: "call-stop"
                        visible: root.callEvent === "ringing"
                        onClicked: root.pluginInterface.decline()
                    }
                    QQC2.Button {
                        text: i18nd("kdeconnect-app", "End")
                        icon.name: "call-stop"
                        visible: root.callEvent === "talking"
                        onClicked: root.pluginInterface.endCall()
                    }
                    QQC2.Button {
                        text: i18nd("kdeconnect-app", "Mute ringer")
                        visible: root.callEvent === "ringing"
                        onClicked: root.pluginInterface.muteRinger()
                    }
                    QQC2.Button {
                        text: i18nd("kdeconnect-app", "Mute mic")
                        visible: root.callEvent === "talking"
                        onClicked: root.pluginInterface.muteMic()
                    }
                    QQC2.Button {
                        text: i18nd("kdeconnect-app", "Speaker")
                        visible: root.callEvent === "talking"
                        onClicked: root.pluginInterface.speakerOn()
                    }
                }
            }
        }

        QQC2.Label { text: i18nd("kdeconnect-app", "Dial"); font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: numberField
                Layout.fillWidth: true
                placeholderText: i18nd("kdeconnect-app", "Number or *# code")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Call")
                icon.name: "call-start"
                onClicked: {
                    if (numberField.text.trim().length)
                        root.pluginInterface.dial(numberField.text.trim())
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18nd("kdeconnect-app", "Search contacts")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Search")
                onClicked: root.pluginInterface.listContacts(searchField.text.trim())
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "All")
                onClicked: root.pluginInterface.listContacts("")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Repeater {
                model: contactModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    text: model.roleName + " — " + model.roleNumber
                    onClicked: numberField.text = model.roleNumber
                    onDoubleClicked: root.pluginInterface.dial(model.roleNumber)
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: root.statusText
            wrapMode: Text.Wrap
            font.family: "monospace"
        }
    }
}