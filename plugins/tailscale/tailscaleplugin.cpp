/**
 * SPDX-FileCopyrightText: 2026 Jarvis / KDE Connect Tailscale integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "tailscaleplugin.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDBusConnection>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>

#include <core/daemon.h>
#include <core/device.h>
#include <core/kdeconnectconfig.h>

K_PLUGIN_CLASS_WITH_JSON(TailscalePlugin, "kdeconnect_tailscale.json")

TailscalePlugin::TailscalePlugin(QObject *parent, const QVariantList &args)
    : KdeConnectPlugin(parent, args)
{
    // Restore previously stored remote IP for this device
    m_remoteIp = config()->getString(QStringLiteral("remoteTailscaleIp"), QString());
    m_selfIp = config()->getString(QStringLiteral("selfTailscaleIp"), QString());

    if (!m_remoteIp.isEmpty()) {
        addToCustomDevices(m_remoteIp);
    }
}

TailscalePlugin::~TailscalePlugin() = default;

void TailscalePlugin::connected()
{
    // When the device becomes reachable, announce our own Tailscale IP
    // so the phone can store it.
    if (!m_selfIp.isEmpty()) {
        announceSelfIp();
    } else {
        // Try to auto-detect our Tailscale IP
        const QString detected = runTailscaleCommand({QStringLiteral("ip"), QStringLiteral("-4")});
        if (isValidTailscaleIp(detected.trimmed())) {
            m_selfIp = detected.trimmed();
            config()->set(QStringLiteral("selfTailscaleIp"), m_selfIp);
            announceSelfIp();
        }
    }
}

void TailscalePlugin::receivePacket(const NetworkPacket &np)
{
    if (np.type() != PACKET_TYPE_TAILSCALE) {
        return;
    }

    const QString action = np.get<QString>(QStringLiteral("action"));
    const QString error = np.get<QString>(QStringLiteral("error"));
    const QString body = np.get<QString>(QStringLiteral("body"));

    // Special handling: the phone is telling us its Tailscale IP
    if (action == QLatin1String("selfIp")) {
        const QString ip = np.get<QString>(QStringLiteral("ip"));
        if (isValidTailscaleIp(ip)) {
            storeAndPropagateRemoteIp(ip);
        }
    }

    Q_EMIT responseReceived(action, body, error);
}

QString TailscalePlugin::dbusPath() const
{
    return QLatin1String("/modules/kdeconnect/devices/%1/tailscale").arg(device()->id());
}

void TailscalePlugin::sendAction(const QString &action, const QVariantMap &extra)
{
    NetworkPacket np(PACKET_TYPE_TAILSCALE);
    np.set(QStringLiteral("action"), action);
    np.set(QStringLiteral("requestId"), QString::number(++m_requestCounter));

    for (auto it = extra.constBegin(); it != extra.constEnd(); ++it) {
        np.set(it.key(), it.value());
    }

    if (!sendPacket(np)) {
        Q_EMIT responseReceived(action, QString(), QStringLiteral("Failed to send packet"));
    }
}

// ---------- Public slots ----------

void TailscalePlugin::requestStatus()
{
    sendAction(QStringLiteral("status"));
}

void TailscalePlugin::setRemoteIp(const QString &ip)
{
    if (!ip.isEmpty() && !isValidTailscaleIp(ip)) {
        Q_EMIT responseReceived(QStringLiteral("setRemoteIp"), QString(), QStringLiteral("Invalid Tailscale IP (expected 100.64.0.0/10)"));
        return;
    }
    storeAndPropagateRemoteIp(ip);
    // Also tell the phone
    QVariantMap extra;
    extra.insert(QStringLiteral("ip"), ip);
    sendAction(QStringLiteral("setRemoteIp"), extra);
}

QString TailscalePlugin::remoteIp() const
{
    return m_remoteIp;
}

void TailscalePlugin::setSelfIp(const QString &ip)
{
    if (!ip.isEmpty() && !isValidTailscaleIp(ip)) {
        return;
    }
    m_selfIp = ip;
    config()->set(QStringLiteral("selfTailscaleIp"), ip);
    announceSelfIp();
}

QString TailscalePlugin::selfIp() const
{
    return m_selfIp;
}

void TailscalePlugin::up()
{
    const QString out = runTailscaleCommand({QStringLiteral("up")});
    Q_EMIT responseReceived(QStringLiteral("up"), out, QString());
}

void TailscalePlugin::down()
{
    const QString out = runTailscaleCommand({QStringLiteral("down")});
    Q_EMIT responseReceived(QStringLiteral("down"), out, QString());
}

void TailscalePlugin::localStatus()
{
    const QString out = runTailscaleCommand({QStringLiteral("status"), QStringLiteral("--json")});
    Q_EMIT responseReceived(QStringLiteral("localStatus"), out, QString());
}

void TailscalePlugin::announceSelfIp()
{
    if (m_selfIp.isEmpty()) {
        return;
    }
    QVariantMap extra;
    extra.insert(QStringLiteral("ip"), m_selfIp);
    sendAction(QStringLiteral("selfIp"), extra);
}

// ---------- Private helpers ----------

void TailscalePlugin::storeAndPropagateRemoteIp(const QString &ip)
{
    if (m_remoteIp == ip) {
        return;
    }
    m_remoteIp = ip;
    config()->set(QStringLiteral("remoteTailscaleIp"), ip);
    addToCustomDevices(ip);
    Q_EMIT remoteIpChanged(ip);
}

void TailscalePlugin::addToCustomDevices(const QString &ip)
{
    if (ip.isEmpty()) {
        return;
    }

    // Add to the global customDevices list used by LanLinkProvider
    QStringList customs = KdeConnectConfig::instance().customDevices();
    if (!customs.contains(ip)) {
        customs.append(ip);
        KdeConnectConfig::instance().setCustomDevices(customs);
        qDebug() << "TailscalePlugin: added" << ip << "to customDevices";
        // Force a network change so the LAN provider rebroadcasts
        Daemon::instance()->forceOnNetworkChange();
    }
}

bool TailscalePlugin::isValidTailscaleIp(const QString &ip) const
{
    // 100.64.0.0/10
    static const QRegularExpression re(QStringLiteral(R"(^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}$)"));
    return re.match(ip).hasMatch();
}

QString TailscalePlugin::runTailscaleCommand(const QStringList &args)
{
    QProcess proc;
    proc.setProgram(QStringLiteral("tailscale"));
    proc.setArguments(args);
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start();
    if (!proc.waitForFinished(8000)) {
        return QStringLiteral("{\"error\":\"tailscale command timed out or not found\"}");
    }
    return QString::fromUtf8(proc.readAll()).trimmed();
}

#include "moc_tailscaleplugin.cpp"
#include "tailscaleplugin.moc"
