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

/**
 * In-app control page for the Shizuku plugin.
 * property pluginInterface is a ShizukuDbusInterface from ShizukuDbusInterfaceFactory.
 */
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

    // Models for neat lists
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

    function addKv(key, value) {
        keyValueModel.append({ key: String(key), value: String(value) })
    }

    function fillKeyValues(obj, prefix) {
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
            if (!obj.hasOwnProperty(k) || skip[k])
                continue
            const v = obj[k]
            if (v !== null && typeof v === "object")
                continue
            addKv(prefix ? (prefix + "." + k) : k, v)
        }
    }

    function handleResponse(action, jsonBody, error) {
        root.lastAction = action
        root.lastError = error || ""
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

        // Packages list
        if (obj.packages && Array.isArray(obj.packages)) {
            root.summaryText = action + " — " + (obj.count !== undefined ? obj.count : obj.packages.length) + " packages"
            for (let i = 0; i < obj.packages.length; i++) {
                const p = obj.packages[i]
                packageModel.append({
                    title: (p.label && p.label.length) ? p.label : (p.packageName || ""),
                    subtitle: (p.packageName || "") + (p.versionName ? ("  ·  " + p.versionName) : ""),
                    packageName: p.packageName || ""
                })
            }
            fillKeyValues(obj, "")
            return
        }

        // Wi‑Fi scan list
        if (obj.networks && Array.isArray(obj.networks)) {
            root.summaryText = action + " — " + (obj.count !== undefined ? obj.count : obj.networks.length) + " networks"
            for (let i = 0; i < obj.networks.length; i++) {
                const n = obj.networks[i]
                const ssid = (n.ssid && n.ssid.length) ? n.ssid : "(hidden)"
                wifiModel.append({
                    title: ssid,
                    subtitle: (n.bssid || "") + (n.level !== undefined ? ("  ·  " + n.level + " dBm") : "")
                        + (n.frequency !== undefined ? ("  ·  " + n.frequency + " MHz") : ""),
                    level: n.level !== undefined ? n.level : -999
                })
            }
            fillKeyValues(obj, "")
            return
        }

        // Bluetooth bonded devices
        if (obj.bondedDevices && Array.isArray(obj.bondedDevices)) {
            root.summaryText = action + " — Bluetooth"
            fillKeyValues(obj, "")
            for (let i = 0; i < obj.bondedDevices.length; i++) {
                const d = obj.bondedDevices[i]
                bluetoothModel.append({
                    title: (d.name && d.name.length) ? d.name : (d.address || "Unknown"),
                    subtitle: d.address || ""
                })
            }
            return
        }

        // Hotspot clients
        if (obj.clients && Array.isArray(obj.clients)) {
            root.summaryText = action + " — " + obj.clients.length + " clients"
            for (let i = 0; i < obj.clients.length; i++) {
                const c = obj.clients[i]
                if (typeof c === "string") {
                    clientModel.append({ title: c, subtitle: "" })
                } else {
                    clientModel.append({
                        title: c.mac || c.address || c.name || JSON.stringify(c),
                        subtitle: c.name || c.ip || ""
                    })
                }
            }
            fillKeyValues(obj, "")
            return
        }

        // Generic object → key/value table
        root.summaryText = action
        fillKeyValues(obj, "")
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

        // ── Status ───────────────────────────────────────────────────────────
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

        // ── Battery ──────────────────────────────────────────────────────────
        QQC2.Label { text: i18nd("kdeconnect-app", "Battery"); font.bold: true }
        QQC2.Button {
            text: i18nd("kdeconnect-app", "Get battery info")
            icon.name: "battery-full"
            Layout.fillWidth: true
            onClicked: root.pluginInterface.requestBattery()
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ── Wi-Fi ────────────────────────────────────────────────────────────
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

        // ── Bluetooth ────────────────────────────────────────────────────────
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

        // ── Hotspot ──────────────────────────────────────────────────────────
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

        // ── Packages ─────────────────────────────────────────────────────────
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

        // ── Response ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                text: i18nd("kdeconnect-app", "Response")
                font.bold: true
                Layout.fillWidth: true
            }
            QQC2.Switch {
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

        // Key / value summary (status, battery, success/error fields, etc.)
        QQC2.Frame {
            Layout.fillWidth: true
            visible: keyValueModel.count > 0 && !root.showRaw
            implicitHeight: Math.min(kvList.contentHeight + 16, Kirigami.Units.gridUnit * 14)

            ListView {
                id: kvList
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                clip: true
                model: keyValueModel
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

                delegate: Item {
                    width: kvList.width
                    height: kvRow.implicitHeight + Kirigami.Units.smallSpacing
                    RowLayout {
                        id: kvRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            text: model.key
                            font.bold: true
                            Layout.preferredWidth: parent.width * 0.35
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            text: model.value
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

        // Packages list
        QQC2.Frame {
            Layout.fillWidth: true
            visible: packageModel.count > 0 && !root.showRaw
            implicitHeight: Math.min(pkgList.contentHeight + 16, Kirigami.Units.gridUnit * 18)

            ListView {
                id: pkgList
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                clip: true
                model: packageModel
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

                delegate: QQC2.ItemDelegate {
                    width: pkgList.width
                    text: model.title
                    onClicked: pkgNameField.text = model.packageName

                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.title
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.bold: true
                        }
                        QQC2.Label {
                            text: model.subtitle
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }
        }

        // Wi‑Fi networks list
        QQC2.Frame {
            Layout.fillWidth: true
            visible: wifiModel.count > 0 && !root.showRaw
            implicitHeight: Math.min(wifiList.contentHeight + 16, Kirigami.Units.gridUnit * 16)

            ListView {
                id: wifiList
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                clip: true
                model: wifiModel
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

                delegate: QQC2.ItemDelegate {
                    width: wifiList.width
                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.title
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.bold: true
                        }
                        QQC2.Label {
                            text: model.subtitle
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }
        }

        // Bluetooth devices list
        QQC2.Frame {
            Layout.fillWidth: true
            visible: bluetoothModel.count > 0 && !root.showRaw
            implicitHeight: Math.min(btList.contentHeight + 16, Kirigami.Units.gridUnit * 12)

            ListView {
                id: btList
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                clip: true
                model: bluetoothModel
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

                delegate: QQC2.ItemDelegate {
                    width: btList.width
                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.title
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.bold: true
                        }
                        QQC2.Label {
                            text: model.subtitle
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }
        }

        // Hotspot clients list
        QQC2.Frame {
            Layout.fillWidth: true
            visible: clientModel.count > 0 && !root.showRaw
            implicitHeight: Math.min(clientList.contentHeight + 16, Kirigami.Units.gridUnit * 10)

            ListView {
                id: clientList
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                clip: true
                model: clientModel
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

                delegate: QQC2.ItemDelegate {
                    width: clientList.width
                    contentItem: ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: model.title
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.bold: true
                        }
                        QQC2.Label {
                            text: model.subtitle
                            visible: model.subtitle.length > 0
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            opacity: 0.7
                        }
                    }
                }
            }
        }

        // Raw JSON (scrollable)
        QQC2.ScrollView {
            id: rawScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 14
            visible: root.showRaw
            clip: true

            QQC2.TextArea {
                id: responseArea
                readOnly: true
                wrapMode: TextEdit.Wrap
                text: root.rawJsonText
                font.family: "monospace"
                placeholderText: i18nd("kdeconnect-app", "Responses from the phone appear here…")
            }
        }

        // Hint when nothing yet
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