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
    property string callSimLabel: ""

    ListModel { id: contactModel }
    ListModel { id: simModel }

    Component.onCompleted: {
        if (root.pluginInterface) {
            root.pluginInterface.listSims()
        }
    }

    Connections {
        target: root.pluginInterface

        function onCallEvent(event, number, contactName, photoBase64, simLabel) {
            root.callEvent = event
            root.callNumber = number
            root.callName = contactName
            root.callSimLabel = simLabel || ""
            if (event === "idle") {
                root.statusText = i18nd("kdeconnect-app", "Idle")
            } else {
                root.statusText = event + " — " + contactName + " " + number
                    + (simLabel ? (" [" + simLabel + "]") : "")
            }
        }

        function onResponseReceived(action, jsonBody, error) {
            if (error && error.length) {
                root.statusText = action + " ERROR: " + error
                return
            }
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
                if (obj.sims) {
                    simModel.clear()
                    for (let i = 0; i < obj.sims.length; i++) {
                        const s = obj.sims[i]
                        const slot = (s.simSlot !== undefined) ? (s.simSlot + 1) : "?"
                        const label = (s.simName || ("SIM " + slot))
                            + (s.carrierName ? (" — " + s.carrierName) : "")
                        simModel.append({
                            roleSubId: s.subscriptionId,
                            roleLabel: label
                        })
                    }
                }
            } catch (e) {
            }
        }
    }

    function placeCall(number) {
        const num = (number || "").trim()
        if (!num.length)
            return
        if (simModel.count <= 1) {
            const sub = simModel.count === 1 ? simModel.get(0).roleSubId : -1
            root.pluginInterface.dial(num, sub)
        } else {
            simDialog.pendingNumber = num
            simDialog.open()
        }
    }

    QQC2.Dialog {
        id: simDialog
        property string pendingNumber: ""
        title: i18nd("kdeconnect-app", "Choose SIM")
        modal: true
        standardButtons: QQC2.Dialog.Cancel
        anchors.centerIn: parent

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18nd("kdeconnect-app", "Call %1 with:", simDialog.pendingNumber)
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Repeater {
                model: simModel
                delegate: QQC2.Button {
                    Layout.fillWidth: true
                    text: model.roleLabel
                    onClicked: {
                        root.pluginInterface.dial(simDialog.pendingNumber, model.roleSubId)
                        simDialog.close()
                    }
                }
            }
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
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: root.callEvent === "ringing"
                          ? i18nd("kdeconnect-app", "Incoming call")
                          : i18nd("kdeconnect-app", "On call")
                    font.bold: true
                }
                QQC2.Label { text: root.callName }
                QQC2.Label {
                    text: root.callNumber
                    opacity: 0.8
                }
                QQC2.Label {
                    text: root.callSimLabel.length
                          ? i18nd("kdeconnect-app", "SIM: %1", root.callSimLabel)
                          : ""
                    visible: root.callSimLabel.length > 0
                    opacity: 0.9
                    font.bold: true
                }

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
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

        QQC2.Label {
            text: i18nd("kdeconnect-app", "Dial")
            font.bold: true
        }
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
                onClicked: root.placeCall(numberField.text)
            }
        }

        // Show known SIMs
        ColumnLayout {
            Layout.fillWidth: true
            visible: simModel.count > 0
            QQC2.Label {
                text: i18nd("kdeconnect-app", "SIMs on phone")
                font.bold: true
            }
            Repeater {
                model: simModel
                delegate: QQC2.Label {
                    text: "• " + model.roleLabel
                    opacity: 0.85
                }
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Refresh SIMs")
                onClicked: root.pluginInterface.listSims()
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
                    onDoubleClicked: root.placeCall(model.roleNumber)
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