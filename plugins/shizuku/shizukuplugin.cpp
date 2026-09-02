/**
 * SPDX-FileCopyrightText: 2026 Jarvis / KDE Connect Shizuku integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "shizukuplugin.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDBusConnection>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>

#include <core/daemon.h>
#include <core/device.h>

K_PLUGIN_CLASS_WITH_JSON(ShizukuPlugin, "kdeconnect_shizuku.json")

void ShizukuPlugin::receivePacket(const NetworkPacket &np)
{
    if (np.type() != PACKET_TYPE_SHIZUKU) {
        return;
    }

    const QString action = np.get<QString>(QStringLiteral("action"));
    const QString error = np.get<QString>(QStringLiteral("error"));
    const QString body = np.get<QString>(QStringLiteral("body"));

    qDebug() << "ShizukuPlugin received reply for action" << action << "error:" << error;

    Q_EMIT responseReceived(action, body, error);
}

QString ShizukuPlugin::dbusPath() const
{
    return QLatin1String("/modules/kdeconnect/devices/%1/shizuku").arg(device()->id());
}

void ShizukuPlugin::sendAction(const QString &action, const QVariantMap &extra)
{
    NetworkPacket np(PACKET_TYPE_SHIZUKU);
    np.set(QStringLiteral("action"), action);
    np.set(QStringLiteral("requestId"), QString::number(++m_requestCounter));

    for (auto it = extra.constBegin(); it != extra.constEnd(); ++it) {
        np.set(it.key(), it.value());
    }

    bool ok = sendPacket(np);
    if (!ok) {
        qWarning() << "ShizukuPlugin: failed to send action" << action;
        Q_EMIT responseReceived(action, QString(), QStringLiteral("Failed to send packet to device"));
    }
}

// ---------- Generic ----------

void ShizukuPlugin::requestStatus()
{
    sendAction(QStringLiteral("status"));
}

void ShizukuPlugin::requestPermission()
{
    sendAction(QStringLiteral("requestPermission"));
}

// ---------- Battery ----------

void ShizukuPlugin::requestBattery()
{
    sendAction(QStringLiteral("battery"));
}

// ---------- Wi-Fi ----------

void ShizukuPlugin::requestWifi()
{
    sendAction(QStringLiteral("wifi"));
}

void ShizukuPlugin::scanWifi()
{
    sendAction(QStringLiteral("wifi.scan"));
}

void ShizukuPlugin::setWifiEnabled(bool enabled)
{
    sendAction(enabled ? QStringLiteral("wifi.enable") : QStringLiteral("wifi.disable"));
}

// ---------- Bluetooth ----------

void ShizukuPlugin::requestBluetooth()
{
    sendAction(QStringLiteral("bluetooth"));
}

void ShizukuPlugin::setBluetoothEnabled(bool enabled)
{
    sendAction(enabled ? QStringLiteral("bluetooth.enable") : QStringLiteral("bluetooth.disable"));
}

// ---------- Hotspot ----------

void ShizukuPlugin::requestHotspot()
{
    sendAction(QStringLiteral("hotspot"));
}

void ShizukuPlugin::getHotspotConfig()
{
    sendAction(QStringLiteral("hotspot.getConfig"));
}

void ShizukuPlugin::setHotspotConfig(const QString &jsonParams)
{
    QVariantMap extra;
    extra.insert(QStringLiteral("params"), jsonParams);
    sendAction(QStringLiteral("hotspot.setConfig"), extra);
}

void ShizukuPlugin::startHotspot()
{
    sendAction(QStringLiteral("hotspot.start"));
}

void ShizukuPlugin::stopHotspot()
{
    sendAction(QStringLiteral("hotspot.stop"));
}

void ShizukuPlugin::getHotspotClients()
{
    sendAction(QStringLiteral("hotspot.clients"));
}

void ShizukuPlugin::banClient(const QString &mac)
{
    QVariantMap extra;
    extra.insert(QStringLiteral("mac"), mac);
    sendAction(QStringLiteral("hotspot.ban"), extra);
}

void ShizukuPlugin::unbanClient(const QString &mac)
{
    QVariantMap extra;
    extra.insert(QStringLiteral("mac"), mac);
    sendAction(QStringLiteral("hotspot.unban"), extra);
}

// ---------- Packages ----------

void ShizukuPlugin::listPackages(bool userOnly)
{
    QVariantMap extra;
    extra.insert(QStringLiteral("userOnly"), userOnly);
    sendAction(QStringLiteral("packages.list"), extra);
}

void ShizukuPlugin::installApk(const QString &path)
{
    QVariantMap extra;
    extra.insert(QStringLiteral("path"), path);
    sendAction(QStringLiteral("packages.install"), extra);
}

void ShizukuPlugin::uninstallPackage(const QString &packageName)
{
    QVariantMap extra;
    extra.insert(QStringLiteral("packageName"), packageName);
    sendAction(QStringLiteral("packages.uninstall"), extra);
}

#include "moc_shizukuplugin.cpp"
#include "shizukuplugin.moc"
