/*
 * SPDX-FileCopyrightText: 2026 Jarvis / KDE Connect Shizuku integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kdeconnect

Kirigami.ScrollablePage {
    id: root

    title: i18nd("kdeconnect-app", "Shizuku controls")
    property QtObject pluginInterface
    property QtObject device

    property string lastAction: ""
    property string lastError: ""
    property string summaryText: ""
    property string rawJsonText: ""
    property bool showRaw: false

    ListModel { id: packageModel }
    ListModel { id: wifiModel }
    ListModel { id: bluetoothModel }
    ListModel { id: clientModel }
    ListModel { id: keyValueModel }

    function clearLists() {
        packageModel.clear()
        wifiModel.clear()
        bluetoothModel.clear()
        clientModel.clear()
        keyValueModel.clear()
    }

    function addKv(k, v) {
        keyValueModel.append({ roleKey: String(k), roleValue: String(v) })
    }

    function fillKeyValues(obj) {
        if (!obj || typeof obj !== "object")
            return
        const skip = {
            "packages": true,
            "networks": true,
            "bondedDevices": true,
            "clients": true,
            "blockedClients": true
        }
        for (const k in obj) {
            if (skip[k])
                continue
            const v = obj[k]
            if (v !== null && typeof v === "object")
                continue
            addKv(k, v)
        }
    }

    function handleResponse(action, jsonBody, error) {
        root.lastAction = action
        root.lastError = error ? error : ""
        root.clearLists()
        root.summaryText = ""
        root.rawJsonText = ""

        if (error && error.length > 0) {
            root.summaryText = action + " — ERROR\n" + error
            root.rawJsonText = error
            return
        }

        let obj = null
        try {
            obj = JSON.parse(jsonBody)
            root.rawJsonText = JSON.stringify(obj, null, 2)
        } catch (e) {
            root.summaryText = action + "\n" + jsonBody
            root.rawJsonText = jsonBody
            return
        }

        if (obj.packages && Array.isArray(obj.packages)) {
            const n = (obj.count !== undefined) ? obj.count : obj.packages.length
            root.summaryText = action + " — " + n + " packages"
            for (let i = 0; i < obj.packages.length; i++) {
                const p = obj.packages[i]
                const label = (p.label && p.label.length) ? p.label : (p.packageName || "")
                const ver = p.versionName ? ("  ·  " + p.versionName) : ""
                packageModel.append({
                    roleTitle: label,
                    roleSubtitle: (p.packageName || "") + ver,
                    rolePackageName: p.packageName || ""
                })
            }
            fillKeyValues(obj)
            return
        }

        if (obj.networks && Array.isArray(obj.networks)) {
            const n = (obj.count !== undefined) ? obj.count : obj.networks.length
            root.summaryText = action + " — " + n + " networks"
            for (let i = 0; i < obj.networks.length; i++) {
                const net = obj.networks[i]
                const ssid = (net.ssid && net.ssid.length) ? net.ssid : "(hidden)"
                let sub = net.bssid || ""
                if (net.level !== undefined)
                    sub += "  ·  " + net.level + " dBm"
                if (net.frequency !== undefined)
                    sub += "  ·  " + net.frequency + " MHz"
                wifiModel.append({ roleTitle: ssid, roleSubtitle: sub })
            }
            fillKeyValues(obj)
            return
        }

        if (obj.bondedDevices && Array.isArray(obj.bondedDevices)) {
            root.summaryText = action + " — Bluetooth"
            fillKeyValues(obj)
            for (let i = 0; i < obj.bondedDevices.length; i++) {
                const d = obj.bondedDevices[i]
                const name = (d.name && d.name.length) ? d.name : (d.address || "Unknown")
                bluetoothModel.append({ roleTitle: name, roleSubtitle: d.address || "" })
            }
            return
        }

        if (obj.clients && Array.isArray(obj.clients)) {
            root.summaryText = action + " — " + obj.clients.length + " clients"
            for (let i = 0; i < obj.clients.length; i++) {
                const c = obj.clients[i]
                if (typeof c === "string") {
                    clientModel.append({ roleTitle: c, roleSubtitle: "" })
                } else {
                    clientModel.append({
                        roleTitle: c.mac || c.address || c.name || JSON.stringify(c),
                        roleSubtitle: c.name || c.ip || ""
                    })
                }
            }
            fillKeyValues(obj)
            return
        }

        root.summaryText = action
        fillKeyValues(obj)
        if (obj.error)
            root.summaryText = action + " — " + obj.error
        else if (obj.success === true)
            root.summaryText = action + " — success"
        else if (obj.success === false)
            root.summaryText = action + " — failed" + (obj.error ? (": " + obj.error) : "")
    }

    Connections {
        target: root.pluginInterface
        function onResponseReceived(action, jsonBody, error) {
            root.handleResponse(action, jsonBody, error)
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            text: i18nd("kdeconnect-app", "Requires Shizuku running and authorised on the phone.")
            visible: true
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            QQC2.Button {
                Kirigami.FormData.label: i18nd("kdeconnect-app", "Status")
                text: i18nd("kdeconnect-app", "Refresh status")
                icon.name: "view-refresh"
                onClicked: root.pluginInterface.requestStatus()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Request permission")
                icon.name: "security-high"
                onClicked: root.pluginInterface.requestPermission()
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Battery"); font.bold: true }
        QQC2.Button {
            text: i18nd("kdeconnect-app", "Get battery info")
            icon.name: "battery-full"
            Layout.fillWidth: true
            onClicked: root.pluginInterface.requestBattery()
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Wi-Fi"); font.bold: true }
        GridLayout {
            columns: 2
            Layout.fillWidth: true
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Status")
                icon.name: "network-wireless"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.requestWifi()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Scan")
                icon.name: "view-refresh"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.scanWifi()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Enable")
                icon.name: "network-connect"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.setWifiEnabled(true)
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Disable")
                icon.name: "network-disconnect"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.setWifiEnabled(false)
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Bluetooth"); font.bold: true }
        GridLayout {
            columns: 3
            Layout.fillWidth: true
            columnSpacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Status")
                icon.name: "network-bluetooth"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.requestBluetooth()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Enable")
                icon.name: "network-connect"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.setBluetoothEnabled(true)
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Disable")
                icon.name: "network-disconnect"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.setBluetoothEnabled(false)
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Hotspot"); font.bold: true }
        GridLayout {
            columns: 2
            Layout.fillWidth: true
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Status")
                icon.name: "network-wireless-hotspot"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.requestHotspot()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Get config")
                icon.name: "configure"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.getHotspotConfig()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Start")
                icon.name: "media-playback-start"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.startHotspot()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Stop")
                icon.name: "media-playback-stop"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.stopHotspot()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "List clients")
                icon.name: "user-group-properties"
                Layout.fillWidth: true
                Layout.columnSpan: 2
                onClicked: root.pluginInterface.getHotspotClients()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: macField
                Layout.fillWidth: true
                placeholderText: i18nd("kdeconnect-app", "MAC aa:bb:cc:dd:ee:ff")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Ban")
                icon.name: "list-remove"
                onClicked: {
                    if (macField.text.trim().length > 0)
                        root.pluginInterface.banClient(macField.text.trim())
                }
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Unban")
                icon.name: "list-add"
                onClicked: {
                    if (macField.text.trim().length > 0)
                        root.pluginInterface.unbanClient(macField.text.trim())
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: hotspotCfgField
                Layout.fillWidth: true
                placeholderText: '{"ssid":"MyHotspot","passphrase":"secret123"}'
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Set config")
                icon.name: "document-save"
                onClicked: {
                    if (hotspotCfgField.text.trim().length > 0)
                        root.pluginInterface.setHotspotConfig(hotspotCfgField.text.trim())
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Packages"); font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                text: i18nd("kdeconnect-app", "List user apps")
                icon.name: "view-list-icons"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.listPackages(true)
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "List all")
                icon.name: "view-list-details"
                Layout.fillWidth: true
                onClicked: root.pluginInterface.listPackages(false)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: apkPathField
                Layout.fillWidth: true
                placeholderText: i18nd("kdeconnect-app", "/sdcard/Download/app.apk  (path on phone)")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Install")
                icon.name: "package-install"
                onClicked: {
                    if (apkPathField.text.trim().length > 0)
                        root.pluginInterface.installApk(apkPathField.text.trim())
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: pkgNameField
                Layout.fillWidth: true
                placeholderText: "com.example.app"
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Uninstall")
                icon.name: "package-remove"
                onClicked: {
                    if (pkgNameField.text.trim().length > 0)
                        root.pluginInterface.uninstallPackage(pkgNameField.text.trim())
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                text: i18nd("kdeconnect-app", "Response")
                font.bold: true
                Layout.fillWidth: true
            }
            QQC2.CheckBox {
                text: i18nd("kdeconnect-app", "Raw JSON")
                checked: root.showRaw
                onToggled: root.showRaw = checked
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: root.summaryText
            wrapMode: Text.Wrap
            visible: root.summaryText.length > 0
            font.bold: true
        }

        // Key / value rows
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            visible: keyValueModel.count > 0 && !root.showRaw

            Repeater {
                model: keyValueModel
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    QQC2.Label {
                        text: model.roleKey
                        font.bold: true
                        Layout.preferredWidth: root.width * 0.35
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        text: model.roleValue
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // Packages
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: packageModel.count > 0 && !root.showRaw

            Repeater {
                model: packageModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    onClicked: pkgNameField.text = model.rolePackageName
                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.roleTitle
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: model.roleSubtitle
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Wi-Fi
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: wifiModel.count > 0 && !root.showRaw

            Repeater {
                model: wifiModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.roleTitle
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: model.roleSubtitle
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Bluetooth
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: bluetoothModel.count > 0 && !root.showRaw

            Repeater {
                model: bluetoothModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.roleTitle
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: model.roleSubtitle
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Clients
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: clientModel.count > 0 && !root.showRaw

            Repeater {
                model: clientModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.roleTitle
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: model.roleSubtitle
                            visible: model.roleSubtitle.length > 0
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Raw JSON — scrollable
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 14
            visible: root.showRaw
            clip: true

            QQC2.TextArea {
                readOnly: true
                wrapMode: TextEdit.Wrap
                text: root.rawJsonText
                font.family: "monospace"
                placeholderText: i18nd("kdeconnect-app", "Responses from the phone appear here…")
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: packageModel.count === 0
                     && wifiModel.count === 0
                     && bluetoothModel.count === 0
                     && clientModel.count === 0
                     && keyValueModel.count === 0
                     && root.summaryText.length === 0
                     && !root.showRaw
            text: i18nd("kdeconnect-app", "Responses from the phone appear here…")
            opacity: 0.6
        }
    }
}