/**
 * SPDX-FileCopyrightText: 2026 Jarvis / KDE Connect Shizuku integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#pragma once

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>

#include <core/kdeconnectplugin.h>

#define PACKET_TYPE_SHIZUKU QStringLiteral("kdeconnect.shizuku")

/**
 * Desktop side of the Shizuku plugin.
 * Exposes D-Bus methods so the plasmoid / CLI / other UI can request
 * privileged actions on the phone.
 */
class ShizukuPlugin : public KdeConnectPlugin
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kdeconnect.device.shizuku")

public:
    using KdeConnectPlugin::KdeConnectPlugin;

    void receivePacket(const NetworkPacket &np) override;
    QString dbusPath() const override;

public Q_SLOTS:
    // Generic
    Q_SCRIPTABLE void requestStatus();
    Q_SCRIPTABLE void requestPermission();

    // Battery
    Q_SCRIPTABLE void requestBattery();

    // Wi-Fi
    Q_SCRIPTABLE void requestWifi();
    Q_SCRIPTABLE void scanWifi();
    Q_SCRIPTABLE void setWifiEnabled(bool enabled);

    // Bluetooth
    Q_SCRIPTABLE void requestBluetooth();
    Q_SCRIPTABLE void setBluetoothEnabled(bool enabled);

    // Hotspot
    Q_SCRIPTABLE void requestHotspot();
    Q_SCRIPTABLE void getHotspotConfig();
    Q_SCRIPTABLE void setHotspotConfig(const QString &jsonParams);
    Q_SCRIPTABLE void startHotspot();
    Q_SCRIPTABLE void stopHotspot();
    Q_SCRIPTABLE void getHotspotClients();
    Q_SCRIPTABLE void banClient(const QString &mac);
    Q_SCRIPTABLE void unbanClient(const QString &mac);

    // Packages
    Q_SCRIPTABLE void listPackages(bool userOnly = true);
    Q_SCRIPTABLE void installApk(const QString &path);
    Q_SCRIPTABLE void uninstallPackage(const QString &packageName);

Q_SIGNALS:
    // Emitted whenever a reply arrives from the phone
    void responseReceived(const QString &action, const QString &jsonBody, const QString &error);

private:
    void sendAction(const QString &action, const QVariantMap &extra = {});
    int m_requestCounter = 0;
};
