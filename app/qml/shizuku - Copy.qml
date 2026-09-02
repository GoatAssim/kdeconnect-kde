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
 * Opened from DevicePage via PluginItem (same pattern as mpris.qml / runcommand.qml).
 *
 * property pluginInterface is a ShizukuDbusInterface created by ShizukuDbusInterfaceFactory.
 */
Kirigami.ScrollablePage {
    id: root

    title: i18nd("kdeconnect-app", "Shizuku controls")
    property QtObject pluginInterface
    property QtObject device

    // Latest reply from the phone
    property string lastAction: ""
    property string lastBody: ""
    property string lastError: ""

    Connections {
        target: root.pluginInterface
        function onResponseReceived(action, jsonBody, error) {
            root.lastAction = action
            root.lastBody = jsonBody
            root.lastError = error
            if (error && error.length > 0) {
                responseArea.text = action + " — ERROR\n" + error
            } else {
                // Pretty-print JSON when possible
                try {
                    const obj = JSON.parse(jsonBody)
                    responseArea.text = action + "\n" + JSON.stringify(obj, null, 2)
                } catch (e) {
                    responseArea.text = action + "\n" + jsonBody
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
        QQC2.Label {
            text: i18nd("kdeconnect-app", "Battery")
            font.bold: true
        }
        QQC2.Button {
            text: i18nd("kdeconnect-app", "Get battery info")
            icon.name: "battery-full"
            Layout.fillWidth: true
            onClicked: root.pluginInterface.requestBattery()
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ── Wi-Fi ────────────────────────────────────────────────────────────
        QQC2.Label {
            text: i18nd("kdeconnect-app", "Wi-Fi")
            font.bold: true
        }
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
        QQC2.Label {
            text: i18nd("kdeconnect-app", "Bluetooth")
            font.bold: true
        }
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
        QQC2.Label {
            text: i18nd("kdeconnect-app", "Hotspot")
            font.bold: true
        }
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
        QQC2.Label {
            text: i18nd("kdeconnect-app", "Packages")
            font.bold: true
        }
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

        // ── Response log ─────────────────────────────────────────────────────
        QQC2.Label {
            text: i18nd("kdeconnect-app", "Response")
            font.bold: true
        }
        QQC2.TextArea {
            id: responseArea
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 12
            readOnly: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            placeholderText: i18nd("kdeconnect-app", "Responses from the phone appear here…")
        }
    }
}
