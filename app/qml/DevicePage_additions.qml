/*
 * ADD these two PluginItem entries to the `plugins` list in
 * app/qml/DevicePage.qml  (inside the property list<QtObject> plugins: [ ... ])
 *
 * Place them in the "control" section, e.g. after Volume control / before SMS.
 */

            PluginItem {
                name: i18nd("kdeconnect-app", "Shizuku controls")
                interfaceFactory: ShizukuDbusInterfaceFactory
                component: "shizuku.qml"
                pluginName: "kdeconnect_shizuku"
                section: "control"
                device: root.currentDevice
            },
            PluginItem {
                name: i18nd("kdeconnect-app", "Tailscale")
                interfaceFactory: TailscaleDbusInterfaceFactory
                component: "tailscale.qml"
                pluginName: "kdeconnect_tailscale"
                section: "control"
                device: root.currentDevice
            },
