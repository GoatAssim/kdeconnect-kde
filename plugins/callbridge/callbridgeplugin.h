/**
 * SPDX-FileCopyrightText: 2026 Jarvis / Call Bridge
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#pragma once

#include <KNotification>
#include <QPointer>
#include <core/kdeconnectplugin.h>

#define PACKET_TYPE_CALLBRIDGE QStringLiteral("kdeconnect.callbridge")

class CallBridgePlugin : public KdeConnectPlugin
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kdeconnect.device.callbridge")

public:
    using KdeConnectPlugin::KdeConnectPlugin;

    void receivePacket(const NetworkPacket &np) override;
    QString dbusPath() const override;

public Q_SLOTS:
    Q_SCRIPTABLE void answer();
    Q_SCRIPTABLE void decline();
    Q_SCRIPTABLE void endCall();
    Q_SCRIPTABLE void muteRinger();
    Q_SCRIPTABLE void unmuteRinger();
    Q_SCRIPTABLE void muteMic();
    Q_SCRIPTABLE void unmuteMic();
    Q_SCRIPTABLE void speakerOn();
    Q_SCRIPTABLE void speakerOff();
    Q_SCRIPTABLE void dial(const QString &number);
    Q_SCRIPTABLE void requestStatus();
    Q_SCRIPTABLE void listContacts(const QString &query = QString());

Q_SIGNALS:
    void responseReceived(const QString &action, const QString &jsonBody, const QString &error);
    void callEvent(const QString &event, const QString &number, const QString &contactName, const QString &photoBase64);

private:
    void sendAction(const QString &action, const QVariantMap &extra = {});
    void handleIncomingEvent(const NetworkPacket &np);

    QPointer<KNotification> m_callNotification;
    int m_requestCounter = 0;
};