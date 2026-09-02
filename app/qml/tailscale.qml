/*
 * SPDX-FileCopyrightText: 2026 Jarvis / KDE Connect Tailscale integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kdeconnect

/**
 * In-app control page for the Tailscale plugin.
 * Same PluginItem pattern as mpris.qml / runcommand.qml.
 */
Kirigami.ScrollablePage {
    id: root

    title: i18nd("kdeconnect-app", "Tailscale")
    property QtObject pluginInterface
    property QtObject device

    Component.onCompleted: loadIps()

    function loadIps() {
        if (!pluginInterface)
            return
        remoteIpField.text = pluginInterface.remoteIp() || ""
        selfIpField.text = pluginInterface.selfIp() || ""
    }

    Connections {
        target: root.pluginInterface
        function onResponseReceived(action, jsonBody, error) {
            if (error && error.length > 0) {
                responseArea.text = action + " — ERROR\n" + error
            } else {
                try {
                    const obj = JSON.parse(jsonBody)
                    responseArea.text = action + "\n" + JSON.stringify(obj, null, 2)
                } catch (e) {
                    responseArea.text = action + "\n" + jsonBody
                }
            }
        }
        function onRemoteIpChanged(ip) {
            remoteIpField.text = ip
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            text: i18nd("kdeconnect-app",
                "Stores the phone’s Tailscale IP so KDE Connect can reach it off-LAN (customDevices).")
            visible: true
        }

        // ── IPs ──────────────────────────────────────────────────────────────
        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                id: remoteIpField
                Kirigami.FormData.label: i18nd("kdeconnect-app", "Phone Tailscale IP")
                placeholderText: "100.x.y.z"
            }
            QQC2.TextField {
                id: selfIpField
                Kirigami.FormData.label: i18nd("kdeconnect-app", "This computer IP")
                placeholderText: "100.x.y.z"
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18nd("kdeconnect-app", "Reload")
                icon.name: "view-refresh"
                onClicked: root.loadIps()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Save phone IP")
                icon.name: "document-save"
                onClicked: root.pluginInterface.setRemoteIp(remoteIpField.text.trim())
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Save desktop IP")
                icon.name: "document-save"
                onClicked: root.pluginInterface.setSelfIp(selfIpField.text.trim())
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Announce → phone")
                icon.name: "network-transmit"
                onClicked: root.pluginInterface.announceSelfIp()
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ── Local daemon ─────────────────────────────────────────────────────
        QQC2.Label {
            text: i18nd("kdeconnect-app", "Local Tailscale daemon")
            font.bold: true
        }
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18nd("kdeconnect-app", "Status")
                icon.name: "view-refresh"
                onClicked: root.pluginInterface.localStatus()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Up")
                icon.name: "network-connect"
                onClicked: root.pluginInterface.up()
            }
            QQC2.Button {
                text: i18nd("kdeconnect-app", "Down")
                icon.name: "network-disconnect"
                onClicked: root.pluginInterface.down()
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ── Phone status ─────────────────────────────────────────────────────
        QQC2.Button {
            text: i18nd("kdeconnect-app", "Request status from phone")
            icon.name: "smartphone"
            Layout.fillWidth: true
            onClicked: root.pluginInterface.requestStatus()
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label {
            text: i18nd("kdeconnect-app", "Response")
            font.bold: true
        }
        QQC2.TextArea {
            id: responseArea
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 10
            readOnly: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            placeholderText: i18nd("kdeconnect-app", "Responses appear here…")
        }
    }
}
