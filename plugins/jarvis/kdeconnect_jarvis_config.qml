/**
 * SPDX-FileCopyrightText: 2026 Jarvis KDE Connect integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick 2.15
import QtQuick.Layouts
import QtQuick.Controls 2.15 as QQC2
import org.kde.kirigami 2.20 as Kirigami
import org.kde.kdeconnect 1.0

Kirigami.ScrollablePage {
    id: root

    property string device

    function parseJson(text, fallback) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return fallback;
        }
    }

    function catalogList() {
        const raw = config.getString("toolCatalog", "[]");
        const parsed = parseJson(raw, []);
        if (parsed && parsed.length) {
            return parsed;
        }
        return [
            { name: "get_datetime", description: "" },
            { name: "get_battery", description: "" },
            { name: "get_wifi_info", description: "" },
            { name: "get_location", description: "" },
            { name: "get_system_info", description: "" },
            { name: "get_disk_usage", description: "" },
            { name: "get_memory_usage", description: "" },
            { name: "run_command", description: "" },
            { name: "run_chain", description: "" },
            { name: "create_command", description: "" },
            { name: "update_command", description: "" },
            { name: "memory_save", description: "" },
            { name: "memory_forget", description: "" },
            { name: "memory_search", description: "" },
            { name: "radio_status", description: "" },
            { name: "wifi_set", description: "" },
            { name: "bluetooth_set", description: "" },
            { name: "git_run", description: "" },
            { name: "take_screenshot", description: "" },
            { name: "web_search", description: "" },
            { name: "web_fetch", description: "" },
            { name: "package_managers", description: "" },
            { name: "package_search", description: "" },
            { name: "package_info", description: "" },
            { name: "package_list", description: "" },
            { name: "package_install", description: "" },
            { name: "package_uninstall", description: "" },
            { name: "spotify_open", description: "" },
            { name: "spotify_now", description: "" },
            { name: "spotify_search", description: "" },
            { name: "spotify_play", description: "" },
            { name: "spotify_control", description: "" },
            { name: "spotify_queue", description: "" },
            { name: "spotify_playlists", description: "" },
            { name: "spotify_suggest", description: "" },
            { name: "spotify_like", description: "" },
            { name: "playnite_list_game_actions", description: "" },
            { name: "playnite_launch_action", description: "" },
            { name: "playnite_find_game", description: "" },
            { name: "playnite_launch_game", description: "" },
            { name: "playnite_library_stats", description: "" },
            { name: "playnite_get_game", description: "" },
            { name: "playnite_update_game", description: "" },
            { name: "playnite_list_frequent", description: "" },
            { name: "playnite_delete_game", description: "" },
            { name: "playnite_get_action", description: "" },
            { name: "playnite_install_game", description: "" },
            { name: "playnite_uninstall_game", description: "" },
            { name: "playnite_manage_game_lists", description: "" },
            { name: "playnite_fetch_game_art", description: "" },
            { name: "playnite_list_missing_art", description: "" },
            { name: "playnite_query_games", description: "" },
            { name: "playnite_list_collections", description: "" },
            { name: "playnite_create_collection", description: "" },
            { name: "playnite_view", description: "" },
            { name: "playnite_app_info", description: "" },
            { name: "playnite_list_addons", description: "" },
            { name: "playnite_list_plugins", description: "" },
            { name: "playnite_notify", description: "" },
            { name: "playnite_auto_categorize", description: "" },
            { name: "playnite_fetch_all_art", description: "" },
            { name: "playnite_get_achievements", description: "" },
            { name: "playnite_get_activity", description: "" },
            { name: "playnite_get_cover", description: "" },
            { name: "playnite_eval", description: "" },
            { name: "playnite_rotate_token", description: "" },
            { name: "playnite_get_skill", description: "" }
        ];
    }

    function allowedMap() {
        return parseJson(config.getString("allowedTools", "{}"), {});
    }

    function writeAllowed(map) {
        config.set("allowedTools", JSON.stringify(map));
        allowedModel.reload();
    }

    function setAll(enabled) {
        const map = {};
        const tools = catalogList();
        for (let i = 0; i < tools.length; i++) {
            map[tools[i].name] = enabled;
        }
        writeAllowed(map);
    }

    actions: [
        Kirigami.Action {
            text: i18nd("kdeconnect-plugins", "Allow all")
            icon.name: "dialog-ok"
            onTriggered: root.setAll(true)
        },
        Kirigami.Action {
            text: i18nd("kdeconnect-plugins", "Deny all")
            icon.name: "dialog-cancel"
            onTriggered: root.setAll(false)
        }
    ]

    KdeConnectPluginConfig {
        id: config
        deviceId: device
        pluginName: "kdeconnect_jarvis"
        onConfigChanged: allowedModel.reload()
    }

    ListView {
        id: view
        model: allowedModel

        header: ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                text: i18nd("kdeconnect-plugins", "Phone tool permissions")
                level: 2
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
            }
            QQC2.Label {
                text: i18nd("kdeconnect-plugins", "When Ask Jarvis runs on a paired phone, only enabled tools may be called. Commands you run from the phone UI are not affected.")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Kirigami.Units.largeSpacing
            }
        }

        delegate: QQC2.ItemDelegate {
            width: ListView.view.width
            contentItem: RowLayout {
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: model.name
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        visible: model.description.length > 0
                        text: model.description
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
                QQC2.Switch {
                    checked: model.allowed
                    onToggled: {
                        const map = root.allowedMap();
                        map[model.name] = checked;
                        root.writeAllowed(map);
                    }
                }
            }
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: view.count === 0
            width: parent.width - Kirigami.Units.gridUnit * 4
            text: i18ndc("kdeconnect-plugins", "@info", "No Jarvis tools found")
            explanation: i18ndc("kdeconnect-plugins", "@info", "Install jarvis on this computer, then reopen these settings.")
        }
    }

    ListModel {
        id: allowedModel

        function reload() {
            clear();
            const tools = root.catalogList();
            const allowed = root.allowedMap();
            for (let i = 0; i < tools.length; i++) {
                const item = tools[i];
                append({
                    name: item.name,
                    description: item.description || "",
                    allowed: !!allowed[item.name]
                });
            }
        }

        Component.onCompleted: reload()
    }
}
