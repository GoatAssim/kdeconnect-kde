/**
 * SPDX-FileCopyrightText: 2026 Jarvis KDE Connect integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#pragma once

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QProcess>
#include <QString>
#include <QUrl>
#include <QWebSocket>

#include <core/kdeconnectplugin.h>

#define PACKET_TYPE_JARVIS QStringLiteral("kdeconnect.jarvis")
#define PACKET_TYPE_JARVIS_REQUEST QStringLiteral("kdeconnect.jarvis.request")

class JarvisPlugin : public KdeConnectPlugin
{
    Q_OBJECT

public:
    explicit JarvisPlugin(QObject *parent, const QVariantList &args);
    ~JarvisPlugin() override;

    void receivePacket(const NetworkPacket &np) override;
    void connected() override;

private:
    QUrl baseUrl() const;
    QUrl wsUrl() const;
    bool ensureServer();
    bool pingServer(QString *error);
    void tryStartNode();
    bool http(const QByteArray &method, const QString &path, const QByteArray &body, QByteArray *response, int *status, int timeoutMs = 15000);
    QJsonDocument httpJson(const QByteArray &method, const QString &path, const QJsonValue &body, int *status, QString *error);
    void ensureWs();
    void sendStatus(const QString &error = QString());
    void sendCommands();
    void sendPacketType(const QString &type, const QVariantMap &extra = {});
    void refreshToolCatalog();
    QString allowedToolsEnv() const;
    QString configApiPath(const QString &which) const;
    void handleCreateCommand(const NetworkPacket &np);
    void handleUpdateCommand(const NetworkPacket &np);
    void handleDeleteCommand(const NetworkPacket &np);
    void handleGetConfig(const NetworkPacket &np);
    void handleSetConfig(const NetworkPacket &np);
    void handleRun(const NetworkPacket &np);
    void handleAsk(const NetworkPacket &np);
    void handleCancel(const QString &kind = QString());
    void handleAiClear();
    void fetchScreenshot(const QString &filename);

    QNetworkAccessManager m_nam;
    QWebSocket m_ws;
    QProcess m_node;
    bool m_startedNode = false;
    int m_runId = 0;
    int m_askId = 0;
    QString m_activeKind;

private Q_SLOTS:
    void onWsTextMessage(const QString &message);
    void onWsError();
};
