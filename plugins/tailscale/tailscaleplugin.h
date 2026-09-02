/**
 * SPDX-FileCopyrightText: 2026 Jarvis / KDE Connect Tailscale integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#pragma once

#include <QObject>
#include <QProcess>
#include <QTimer>

#include <core/kdeconnectplugin.h>

#define PACKET_TYPE_TAILSCALE QStringLiteral("kdeconnect.tailscale")

/**
 * Desktop Tailscale plugin.
 *
 * - Stores the phone's Tailscale IP (per device).
 * - Automatically adds that IP to the global customDevices list so KDE Connect
 *   will try to connect to it when the phone is not on the same LAN.
 * - Can start/stop/query the local Tailscale daemon.
 * - Receives the phone's self-IP announcements and keeps customDevices in sync.
 */
class TailscalePlugin : public KdeConnectPlugin
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kdeconnect.device.tailscale")

public:
    explicit TailscalePlugin(QObject *parent, const QVariantList &args);
    ~TailscalePlugin() override;

    void receivePacket(const NetworkPacket &np) override;
    void connected() override;
    QString dbusPath() const override;

public Q_SLOTS:
    Q_SCRIPTABLE void requestStatus();
    Q_SCRIPTABLE void setRemoteIp(const QString &ip);
    Q_SCRIPTABLE QString remoteIp() const;
    Q_SCRIPTABLE void setSelfIp(const QString &ip);
    Q_SCRIPTABLE QString selfIp() const;

    Q_SCRIPTABLE void up();
    Q_SCRIPTABLE void down();
    Q_SCRIPTABLE void localStatus(); // query local tailscale status
    Q_SCRIPTABLE void announceSelfIp(); // tell the phone our Tailscale IP

Q_SIGNALS:
    void responseReceived(const QString &action, const QString &jsonBody, const QString &error);
    void remoteIpChanged(const QString &ip);

private:
    void sendAction(const QString &action, const QVariantMap &extra = {});
    void storeAndPropagateRemoteIp(const QString &ip);
    void addToCustomDevices(const QString &ip);
    bool isValidTailscaleIp(const QString &ip) const;
    QString runTailscaleCommand(const QStringList &args);

    int m_requestCounter = 0;
    QString m_remoteIp;
    QString m_selfIp;
};
