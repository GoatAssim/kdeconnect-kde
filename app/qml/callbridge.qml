import QtQuick
import QtQuick.Window
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
    property string callPhoto: ""
    property bool ringerMuted: false
    property bool micMuted: false
    property bool speakerEnabled: false

    readonly property string callInitial: callName.length ? callName.trim().charAt(0).toUpperCase() : "#"

    ListModel { id: contactModel }
    ListModel { id: simModel }

    function refreshMeta() {
        console.log("[callbridge QML DEBUG] refreshMeta called, pluginInterface=", root.pluginInterface)
        if (!root.pluginInterface) {
            root.statusText = "No pluginInterface (plugin not loaded on PC or not paired)."
            return
        }
        root.pluginInterface.listSims()
        root.pluginInterface.listContacts("")
    }

    Component.onCompleted: {
        console.log("[callbridge QML DEBUG] onCompleted, pluginInterface=", root.pluginInterface)
        refreshMeta()
    }

    Connections {
        target: root.pluginInterface

        function onCallEvent(event, number, contactName, photoBase64, simLabel) {
            console.log("[callbridge QML DEBUG] onCallEvent fired", event, number)
            root.callEvent = event
            root.callNumber = number || ""
            root.callName = contactName || number || ""
            root.callSimLabel = simLabel || ""
            root.callPhoto = photoBase64 || ""
            root.statusText = "EVENT " + event + " | " + root.callName + " | " + root.callNumber
                + (root.callSimLabel ? (" | SIM " + root.callSimLabel) : "")

            if (event === "idle") {
                // Reset toggle states once the call ends so the next call starts clean
                root.ringerMuted = false
                root.micMuted = false
                root.speakerEnabled = false
            }
        }

        function onResponseReceived(action, jsonBody, error) {
            console.log("[callbridge QML DEBUG] onResponseReceived fired", action, "bodyLen=", jsonBody ? jsonBody.length : -1, "error=", error)
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
                    const name = s.simName && s.simName.length ? s.simName : ("SIM " + slot)
                    simModel.append({
                        roleSubId: s.subscriptionId || -1,
                        roleName: name,
                        roleCarrier: s.carrierName || ""
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

    // --- Reusable small "avatar" badge: photo if we have one, otherwise initials ---
    component AvatarBadge: Item {
        property string photo: ""
        property string initial: "#"
        property real diameter: Kirigami.Units.iconSizes.medium

        implicitWidth: diameter
        implicitHeight: diameter

        Rectangle {
            id: badgeBg
            anchors.fill: parent
            radius: width / 2
            color: Kirigami.Theme.highlightColor
            visible: !photoImg.visible
            QQC2.Label {
                anchors.centerIn: parent
                text: initial
                color: Kirigami.Theme.highlightedTextColor
                font.bold: true
                font.pixelSize: badgeBg.height * 0.45
            }
        }

        Image {
            id: photoImg
            anchors.fill: parent
            visible: photo.length > 0
            fillMode: Image.PreserveAspectCrop
            source: photo.length ? ("data:image/png;base64," + photo) : ""
        }
    }

    // --- SIM picker: name shown prominently, carrier as a subtitle, plus an icon ---
    QQC2.Dialog {
        id: simDialog
        property string pendingNumber: ""
        title: i18nd("kdeconnect-app", "Choose SIM")
        modal: true
        standardButtons: QQC2.Dialog.Cancel
        anchors.centerIn: parent
        width: Math.min(root.width * 0.9, 380)

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing
            QQC2.Label {
                text: i18nd("kdeconnect-app", "Call %1 with:", simDialog.pendingNumber)
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Repeater {
                model: simModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    onClicked: {
                        root.pluginInterface.dial(simDialog.pendingNumber, model.roleSubId)
                        simDialog.close()
                    }
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Kirigami.Icon {
                            source: "network-mobile"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: model.roleName
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            QQC2.Label {
                                visible: model.roleCarrier.length > 0
                                text: model.roleCarrier
                                opacity: 0.7
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Floating call window: shown on its own whenever a call is ringing or active ---
    Window {
        id: callWindow
        visible: root.callEvent === "ringing" || root.callEvent === "talking"
        flags: Qt.Dialog
        width: 340
        height: 460
        minimumWidth: 300
        minimumHeight: 420
        title: root.callEvent === "ringing"
            ? i18nd("kdeconnect-app", "Incoming Call")
            : i18nd("kdeconnect-app", "On Call")
        color: Kirigami.Theme.backgroundColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.5
            spacing: Kirigami.Units.largeSpacing

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

            AvatarBadge {
                Layout.alignment: Qt.AlignHCenter
                diameter: Kirigami.Units.gridUnit * 6
                photo: root.callPhoto
                initial: root.callInitial
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.callEvent === "ringing"
                    ? i18nd("kdeconnect-app", "Incoming call")
                    : i18nd("kdeconnect-app", "On call")
                opacity: 0.7
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: root.callName
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.5
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.callNumber
                opacity: 0.8
                visible: root.callNumber.length > 0
            }

            Kirigami.Chip {
                Layout.alignment: Qt.AlignHCenter
                visible: root.callSimLabel.length > 0
                text: root.callSimLabel
                icon.name: "network-mobile"
                closable: false
                checkable: false
            }

            Item { Layout.fillHeight: true }

            GridLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                columns: 3
                rowSpacing: Kirigami.Units.largeSpacing
                columnSpacing: Kirigami.Units.largeSpacing

                // Ringing controls
                QQC2.RoundButton {
                    visible: root.callEvent === "ringing"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    display: QQC2.AbstractButton.TextUnderIcon
                    icon.name: "call-start"
                    text: i18nd("kdeconnect-app", "Answer")
                    onClicked: root.pluginInterface.answer()
                }
                QQC2.RoundButton {
                    visible: root.callEvent === "ringing"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    display: QQC2.AbstractButton.TextUnderIcon
                    icon.name: "call-stop"
                    text: i18nd("kdeconnect-app", "Decline")
                    onClicked: root.pluginInterface.decline()
                }
                QQC2.RoundButton {
                    visible: root.callEvent === "ringing"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    display: QQC2.AbstractButton.TextUnderIcon
                    checkable: true
                    checked: root.ringerMuted
                    icon.name: checked ? "audio-volume-muted" : "notifications-active"
                    text: checked ? i18nd("kdeconnect-app", "Ringer off") : i18nd("kdeconnect-app", "Mute ringer")
                    onToggled: {
                        root.ringerMuted = checked
                        if (checked)
                            root.pluginInterface.muteRinger()
                        else
                            root.pluginInterface.unmuteRinger()
                    }
                }

                // Talking controls
                QQC2.RoundButton {
                    visible: root.callEvent === "talking"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    display: QQC2.AbstractButton.TextUnderIcon
                    icon.name: "call-stop"
                    text: i18nd("kdeconnect-app", "End")
                    onClicked: root.pluginInterface.endCall()
                }
                QQC2.RoundButton {
                    visible: root.callEvent === "talking"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    display: QQC2.AbstractButton.TextUnderIcon
                    checkable: true
                    checked: root.micMuted
                    icon.name: checked ? "microphone-sensitivity-muted-symbolic" : "audio-input-microphone"
                    text: checked ? i18nd("kdeconnect-app", "Unmute mic") : i18nd("kdeconnect-app", "Mute mic")
                    onToggled: {
                        root.micMuted = checked
                        if (checked)
                            root.pluginInterface.muteMic()
                        else
                            root.pluginInterface.unmuteMic()
                    }
                }
                QQC2.RoundButton {
                    visible: root.callEvent === "talking"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    display: QQC2.AbstractButton.TextUnderIcon
                    checkable: true
                    checked: root.speakerEnabled
                    icon.name: checked ? "audio-speakers-symbolic" : "audio-volume-high"
                    text: i18nd("kdeconnect-app", "Speaker")
                    onToggled: {
                        root.speakerEnabled = checked
                        if (checked)
                            root.pluginInterface.speakerOn()
                        else
                            root.pluginInterface.speakerOff()
                    }
                }
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
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
            spacing: Kirigami.Units.largeSpacing
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Reload SIMs + Contacts")
                icon.name: "view-refresh"
                onClicked: root.refreshMeta()
            }
            QQC2.Label {
                text: "SIMs: " + simModel.count + " | Contacts: " + contactModel.count
                opacity: 0.7
            }
        }

        // Compact banner pointing at the popped-out call window, so the main
        // page doesn't also try to cram in the full call UI.
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Positive
            visible: root.callEvent === "ringing" || root.callEvent === "talking"
            text: (root.callEvent === "ringing"
                    ? i18nd("kdeconnect-app", "Incoming call from %1 — see the call window.", root.callName)
                    : i18nd("kdeconnect-app", "On call with %1 — see the call window.", root.callName))
        }

        QQC2.Label { text: i18nd("kdeconnect-app", "Dial"); font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
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

        ColumnLayout {
            visible: simModel.count > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18nd("kdeconnect-app", "SIMs on phone"); font.bold: true }
            Repeater {
                model: simModel
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: "network-mobile"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    QQC2.Label {
                        text: model.roleName
                        font.bold: true
                    }
                    QQC2.Label {
                        visible: model.roleCarrier.length > 0
                        text: "— " + model.roleCarrier
                        opacity: 0.7
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            QQC2.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18nd("kdeconnect-app", "Search contacts")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Search")
                icon.name: "search"
                onClicked: root.pluginInterface.listContacts(searchField.text.trim())
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "All")
                icon.name: "view-list-details"
                onClicked: root.pluginInterface.listContacts("")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: contactModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    onClicked: numberField.text = model.roleNumber
                    onDoubleClicked: root.placeCall(model.roleNumber)
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        AvatarBadge {
                            diameter: Kirigami.Units.iconSizes.medium
                            initial: model.roleName.length ? model.roleName.trim().charAt(0).toUpperCase() : "#"
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: model.roleName
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            QQC2.Label {
                                text: model.roleNumber
                                opacity: 0.7
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                        QQC2.ToolButton {
                            icon.name: "call-start"
                            onClicked: root.placeCall(model.roleNumber)
                        }
                    }
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
