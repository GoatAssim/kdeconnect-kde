/*
 * SPDX-FileCopyrightText: 2026 Jarvis / KDE Connect Shizuku integration
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

    function logLine(msg) {
        if (responseArea.text.length > 0)
            responseArea.text += "\n"
        responseArea.text += msg
    }

    function callMethod(name, args) {
        args = args || []
        logLine("→ " + name + (args.length ? "(" + args.join(", ") + ")" : "()"))

        if (!pluginInterface) {
            logLine("ERROR: pluginInterface is null — factory did not create the D-Bus proxy")
            return
        }

        try {
            if (typeof pluginInterface[name] === "function") {
                pluginInterface[name].apply(pluginInterface, args)
                return
            }
            logLine("ERROR: method not found on interface: " + name)
        } catch (e) {
            logLine("direct call failed: " + e)
        }

        try {
            if (device && device.pluginCall && args.length === 0) {
                logLine("(fallback device.pluginCall)")
                device.pluginCall("shizuku", name)
            }
        } catch (e2) {
            logLine("fallback failed: " + e2)
        }
    }

    Component.onCompleted: {
        if (!pluginInterface) {
            logLine("WARN: no pluginInterface on open")
        } else {
            logLine("pluginInterface OK")
            callMethod("requestStatus")
        }
    }

    Connections {
        target: root.pluginInterface
        enabled: root.pluginInterface !== null

        function onResponseReceived(action, jsonBody, error) {
            if (error && error.length > 0) {
                logLine("← " + action + " ERROR: " + error)
            } else {
                try {
                    logLine("← " + action + "\n" + JSON.stringify(JSON.parse(jsonBody), null, 2))
                } catch (e) {
                    logLine("← " + action + "\n" + jsonBody)
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
            text: i18nd("kdeconnect-app", "Requires Shizuku running and authorised on the phone.")
            visible: true
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            QQC2.Button {
                Kirigami.FormData.label: i18nd("kdeconnect-app", "Status")
                text: i18nd("kdeconnect-app", "Refresh status")
                icon.name: "view-refresh"
                onClicked: callMethod("requestStatus")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Request permission")
                icon.name: "security-high"
                onClicked: callMethod("requestPermission")
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Battery"); font.bold: true }
        QQC2.Button {
            text: i18nd("kdeconnect-app", "Get battery info")
            icon.name: "battery-full"
            Layout.fillWidth: true
            onClicked: callMethod("requestBattery")
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Wi-Fi"); font.bold: true }
        GridLayout {
            columns: 2
            Layout.fillWidth: true
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Status"); icon.name: "network-wireless"
                Layout.fillWidth: true
                onClicked: callMethod("requestWifi")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Scan"); icon.name: "view-refresh"
                Layout.fillWidth: true
                onClicked: callMethod("scanWifi")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Enable"); icon.name: "network-connect"
                Layout.fillWidth: true
                onClicked: callMethod("setWifiEnabled", [true])
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Disable"); icon.name: "network-disconnect"
                Layout.fillWidth: true
                onClicked: callMethod("setWifiEnabled", [false])
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Bluetooth"); font.bold: true }
        GridLayout {
            columns: 3
            Layout.fillWidth: true
            columnSpacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Status"); icon.name: "network-bluetooth"
                Layout.fillWidth: true
                onClicked: callMethod("requestBluetooth")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Enable"); Layout.fillWidth: true
                onClicked: callMethod("setBluetoothEnabled", [true])
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Disable"); Layout.fillWidth: true
                onClicked: callMethod("setBluetoothEnabled", [false])
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
                text: i18nd("kdeconnect-app", "Status"); Layout.fillWidth: true
                onClicked: callMethod("requestHotspot")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Get config"); Layout.fillWidth: true
                onClicked: callMethod("getHotspotConfig")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Start"); icon.name: "media-playback-start"
                Layout.fillWidth: true
                onClicked: callMethod("startHotspot")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Stop"); icon.name: "media-playback-stop"
                Layout.fillWidth: true
                onClicked: callMethod("stopHotspot")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "List clients"); Layout.fillWidth: true
                Layout.columnSpan: 2
                onClicked: callMethod("getHotspotClients")
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
                onClicked: {
                    if (macField.text.trim().length)
                        callMethod("banClient", [macField.text.trim()])
                }
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Unban")
                onClicked: {
                    if (macField.text.trim().length)
                        callMethod("unbanClient", [macField.text.trim()])
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
                onClicked: {
                    if (hotspotCfgField.text.trim().length)
                        callMethod("setHotspotConfig", [hotspotCfgField.text.trim()])
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Packages"); font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                text: i18nd("kdeconnect-app", "List user apps")
                Layout.fillWidth: true
                onClicked: callMethod("listPackages", [true])
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "List all")
                Layout.fillWidth: true
                onClicked: callMethod("listPackages", [false])
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: apkPathField
                Layout.fillWidth: true
                placeholderText: i18nd("kdeconnect-app", "/sdcard/Download/app.apk")
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Install")
                onClicked: {
                    if (apkPathField.text.trim().length)
                        callMethod("installApk", [apkPathField.text.trim()])
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
                onClicked: {
                    if (pkgNameField.text.trim().length)
                        callMethod("uninstallPackage", [pkgNameField.text.trim()])
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label { text: i18nd("kdeconnect-app", "Response"); font.bold: true }
        QQC2.TextArea {
            id: responseArea
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 12
            readOnly: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            placeholderText: i18nd("kdeconnect-app", "Responses appear here…")
        }
    }
}
