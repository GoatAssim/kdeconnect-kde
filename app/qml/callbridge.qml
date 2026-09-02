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

    property string statusText: "Open this page, then grant Phone + Call logs + Contacts on the phone."
    property string callEvent: "idle"
    property string callName: ""
    property string callNumber: ""
    property string callSimLabel: ""

    ListModel { id: contactModel }
    ListModel { id: simModel }

    function refreshMeta() {
        if (!root.pluginInterface) {
            root.statusText = "No pluginInterface (plugin not loaded on PC or not paired)."
            return
        }
        root.pluginInterface.listSims()
        root.pluginInterface.listContacts("")
    }

    Component.onCompleted: refreshMeta()

    Connections {
        target: root.pluginInterface

        function onCallEvent(event, number, contactName, photoBase64, simLabel) {
            root.callEvent = event
            root.callNumber = number || ""
            root.callName = contactName || number || ""
            root.callSimLabel = simLabel || ""
            root.statusText = "EVENT " + event + " | " + root.callName + " | " + root.callNumber
                + (root.callSimLabel ? (" | SIM " + root.callSimLabel) : "")
        }

        function onResponseReceived(action, jsonBody, error) {
            if (error && error.length) {
                root.statusText = action + " ERROR: " + error
                return
            }

            root.statusText = action + " OK (" + (jsonBody ? jsonBody.length : 0) + " chars)"

            if (!jsonBody || !jsonBody.length) {
                root.statusText = action + " — empty body (phone plugin may be old or permission denied)"
                return
            }

            let obj = null
            try {
                obj = JSON.parse(jsonBody)
            } catch (e) {
                root.statusText = action + " — bad JSON: " + jsonBody.substring(0, 200)
                return
            }

            if (obj.error) {
                root.statusText = action + " — " + obj.error
            }

            if (obj.sims) {
                simModel.clear()
                for (let i = 0; i < obj.sims.length; i++) {
                    const s = obj.sims[i]
                    const slot = (s.simSlot !== undefined && s.simSlot >= 0) ? (s.simSlot + 1) : "?"
                    const label = (s.simName || ("SIM " + slot))
                        + (s.carrierName ? (" — " + s.carrierName) : "")
                    simModel.append({
                        roleSubId: s.subscriptionId || -1,
                        roleLabel: label
                    })
                }
                root.statusText = "SIMs loaded: " + simModel.count
            }

            if (obj.contacts) {
                contactModel.clear()
                for (let i = 0; i < obj.contacts.length; i++) {
                    contactModel.append({
                        roleName: obj.contacts[i].name || "",
                        roleNumber: obj.contacts[i].number || ""
                    })
                }
                root.statusText = "Contacts loaded: " + contactModel.count
                    + (obj.error ? (" (" + obj.error + ")") : "")
            }
        }
    }

    function placeCall(number) {
        const num = (number || "").trim()
        if (!num.length) {
            root.statusText = "Enter a number first"
            return
        }
        if (!root.pluginInterface) return

        // Always show picker if we know 2+ SIMs
        if (simModel.count >= 2) {
            simDialog.pendingNumber = num
            simDialog.open()
            return
        }
        if (simModel.count === 1) {
            root.pluginInterface.dial(num, simModel.get(0).roleSubId)
            return
        }
        // Unknown SIMs — still try default, but ask phone again
        root.pluginInterface.listSims()
        root.pluginInterface.dial(num, -1)
        root.statusText = "Dialing on default SIM (listSims returned 0). Check phone READ_PHONE_STATE."
    }

    QQC2.Dialog {
        id: simDialog
        property string pendingNumber: ""
        title: i18nd("kdeconnect-app", "Choose SIM")
        modal: true
        standardButtons: QQC2.Dialog.Cancel
        anchors.centerIn: parent
        width: Math.min(root.width * 0.9, 360)

        ColumnLayout {
            anchors.fill: parent
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
            text: i18nd("kdeconnect-app", "Grant Phone, Call logs, and Contacts on the phone. Audio stays on the phone.")
            visible: true
        }

        RowLayout {
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Reload SIMs + Contacts")
                icon.name: "view-refresh"
                onClicked: root.refreshMeta()
            }
            QQC2.Label {
                text: "SIMs: " + simModel.count + " | Contacts: " + contactModel.count
            }
        }

        QQC2.Frame {
            Layout.fillWidth: true
            visible: root.callEvent === "ringing" || root.callEvent === "talking"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                QQC2.Label {
                    text: root.callEvent === "ringing" ? "Incoming call" : "On call"
                    font.bold: true
                }
                QQC2.Label { text: root.callName }
                QQC2.Label { text: root.callNumber; opacity: 0.8 }
                QQC2.Label {
                    text: root.callSimLabel.length ? ("SIM: " + root.callSimLabel) : ""
                    visible: root.callSimLabel.length > 0
                    font.bold: true
                }
                RowLayout {
                    QQC2.Button {
                        text: "Answer"
                        visible: root.callEvent === "ringing"
                        onClicked: root.pluginInterface.answer()
                    }
                    QQC2.Button {
                        text: "Decline"
                        visible: root.callEvent === "ringing"
                        onClicked: root.pluginInterface.decline()
                    }
                    QQC2.Button {
                        text: "End"
                        visible: root.callEvent === "talking"
                        onClicked: root.pluginInterface.endCall()
                    }
                    QQC2.Button {
                        text: "Mute ringer"
                        visible: root.callEvent === "ringing"
                        onClicked: root.pluginInterface.muteRinger()
                    }
                    QQC2.Button {
                        text: "Mute mic"
                        visible: root.callEvent === "talking"
                        onClicked: root.pluginInterface.muteMic()
                    }
                    QQC2.Button {
                        text: "Speaker"
                        visible: root.callEvent === "talking"
                        onClicked: root.pluginInterface.speakerOn()
                    }
                }
            }
        }

        QQC2.Label { text: "Dial"; font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: numberField
                Layout.fillWidth: true
                placeholderText: "Number or *# code"
            }
            QQC2.Button {
                text: "Call"
                icon.name: "call-start"
                onClicked: root.placeCall(numberField.text)
            }
        }

        ColumnLayout {
            visible: simModel.count > 0
            Layout.fillWidth: true
            QQC2.Label { text: "SIMs on phone"; font.bold: true }
            Repeater {
                model: simModel
                delegate: QQC2.Label { text: "• " + model.roleLabel }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search contacts"
            }
            QQC2.Button {
                text: "Search"
                onClicked: root.pluginInterface.listContacts(searchField.text.trim())
            }
            QQC2.Button {
                text: "All"
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