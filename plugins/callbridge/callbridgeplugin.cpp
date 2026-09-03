/**
 * SPDX-FileCopyrightText: 2026 Jarvis / Call Bridge
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "callbridgeplugin.h"

#include <KLocalizedString>
#include <KNotification>
#include <KPluginFactory>
#include <QPixmap>

#include <core/device.h>

K_PLUGIN_CLASS_WITH_JSON(CallBridgePlugin, "kdeconnect_callbridge.json")

void CallBridgePlugin::receivePacket(const NetworkPacket &np)
{
    if (np.type() != PACKET_TYPE_CALLBRIDGE)
        return;

    const QString action = np.get<QString>(QStringLiteral("action"));

    // Only true call-state events (never contacts / sims / dial replies)
    if (action == QLatin1String("event")) {
        handleIncomingEvent(np);
        return;
    }

    const QString error = np.get<QString>(QStringLiteral("error"));
    const QString body = np.get<QString>(QStringLiteral("body"));
    Q_EMIT responseReceived(action, body, error);
}

void CallBridgePlugin::handleIncomingEvent(const NetworkPacket &np)
{
    if (np.get<bool>(QStringLiteral("isCancel"))) {
        if (m_callNotification)
            m_callNotification->close();
        Q_EMIT callEvent(QStringLiteral("idle"), QString(), QString(), QString(), QString());
        return;
    }

    const QString event = np.get<QString>(QStringLiteral("event"));
    const QString number = np.get<QString>(QStringLiteral("phoneNumber"));
    const QString name = np.get<QString>(QStringLiteral("contactName"), number);
    const QByteArray thumb = QByteArray::fromBase64(np.get<QByteArray>(QStringLiteral("phoneThumbnail")));

    const QString simName = np.get<QString>(QStringLiteral("simName"));
    const QString simCarrier = np.get<QString>(QStringLiteral("simCarrier"));
    const int simSlot = np.get<int>(QStringLiteral("simSlot"), -1);

    QString simLabel;
    if (!simName.isEmpty())
        simLabel = simName;
    else if (simSlot >= 0)
        simLabel = i18n("SIM %1", simSlot + 1);
    if (!simCarrier.isEmpty()) {
        if (!simLabel.isEmpty())
            simLabel += QStringLiteral(" (%1)").arg(simCarrier);
        else
            simLabel = simCarrier;
    }

    Q_EMIT callEvent(event, number, name, QString::fromLatin1(np.get<QByteArray>(QStringLiteral("phoneThumbnail"))), simLabel);

    if (event == QLatin1String("talking")) {
        if (m_callNotification)
            m_callNotification->close();
        return;
    }

    if (event != QLatin1String("ringing"))
        return;

    if (!m_callNotification)
        m_callNotification = new KNotification(QStringLiteral("callReceived"), KNotification::Persistent);

    m_callNotification->setComponentName(QStringLiteral("kdeconnect"));
    m_callNotification->setTitle(device()->name());

    QString text = i18n("Incoming call from %1", name);
    if (!simLabel.isEmpty())
        text += QStringLiteral("\n") + i18n("on %1", simLabel);
    m_callNotification->setText(text);
    m_callNotification->setIconName(QStringLiteral("call-start"));

    if (!thumb.isEmpty()) {
        QPixmap photo;
        photo.loadFromData(thumb, "JPEG");
        if (!photo.isNull())
            m_callNotification->setPixmap(photo);
    }

    m_callNotification->clearActions();
    auto *answerAct = m_callNotification->addAction(i18n("Answer"));
    auto *declineAct = m_callNotification->addAction(i18n("Decline"));
    auto *muteAct = m_callNotification->addAction(i18n("Mute"));

    connect(answerAct, &KNotificationAction::activated, this, &CallBridgePlugin::answer);
    connect(declineAct, &KNotificationAction::activated, this, &CallBridgePlugin::decline);
    connect(muteAct, &KNotificationAction::activated, this, &CallBridgePlugin::muteRinger);

    m_callNotification->sendEvent();
}

QString CallBridgePlugin::dbusPath() const
{
    return QLatin1String("/modules/kdeconnect/devices/%1/callbridge").arg(device()->id());
}

void CallBridgePlugin::sendAction(const QString &action, const QVariantMap &extra)
{
    NetworkPacket np(PACKET_TYPE_CALLBRIDGE);
    np.set(QStringLiteral("action"), action);
    np.set(QStringLiteral("requestId"), QString::number(++m_requestCounter));
    for (auto it = extra.constBegin(); it != extra.constEnd(); ++it)
        np.set(it.key(), it.value());
    if (!sendPacket(np))
        Q_EMIT responseReceived(action, QString(), QStringLiteral("Failed to send packet (device offline?)"));
}

void CallBridgePlugin::answer()
{
    sendAction(QStringLiteral("answer"));
}
void CallBridgePlugin::decline()
{
    sendAction(QStringLiteral("decline"));
}
void CallBridgePlugin::endCall()
{
    sendAction(QStringLiteral("end"));
}
void CallBridgePlugin::muteRinger()
{
    sendAction(QStringLiteral("muteRinger"));
}
void CallBridgePlugin::unmuteRinger()
{
    sendAction(QStringLiteral("unmuteRinger"));
}
void CallBridgePlugin::muteMic()
{
    sendAction(QStringLiteral("muteMic"));
}
void CallBridgePlugin::unmuteMic()
{
    sendAction(QStringLiteral("unmuteMic"));
}
void CallBridgePlugin::speakerOn()
{
    sendAction(QStringLiteral("speakerOn"));
}
void CallBridgePlugin::speakerOff()
{
    sendAction(QStringLiteral("speakerOff"));
}
void CallBridgePlugin::requestStatus()
{
    sendAction(QStringLiteral("status"));
}

void CallBridgePlugin::listContacts(const QString &query)
{
    sendAction(QStringLiteral("contacts.list"), {{QStringLiteral("query"), query}});
}

void CallBridgePlugin::listSims()
{
    sendAction(QStringLiteral("sims.list"));
}

void CallBridgePlugin::dial(const QString &number, int subscriptionId)
{
    QVariantMap extra;
    extra.insert(QStringLiteral("number"), number);
    extra.insert(QStringLiteral("subscriptionId"), subscriptionId);
    sendAction(QStringLiteral("dial"), extra);
}

#include "callbridgeplugin.moc"
#include "moc_callbridgeplugin.cpp"
