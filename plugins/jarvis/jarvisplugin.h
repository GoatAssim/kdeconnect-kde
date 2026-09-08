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
#include <QPair>
#include <QPointer>
#include <QProcess>
#include <QString>
#include <QUrl>
#include <QVector>
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
    void handleGetConfigList();
    void handleGetConfig(const NetworkPacket &np);
    void handleSetConfig(const NetworkPacket &np);
    void handleRun(const NetworkPacket &np);
    void handleAsk(const NetworkPacket &np);
    void handleCancel(const QString &kind = QString());
    void handleAiClear();
    void handleAskConfirmResponse(const NetworkPacket &np);
    void fetchScreenshot(const QString &filename);
    QString ensureConversationId();
    // Reveal in Explorer / Open location / Open file for a path the phone
    // spotted in Jarvis's own reply (see collectFileActionCandidates) —
    // proxied through the same /api/tools/run endpoint the web debug
    // dashboard's buttons use (jarvis-cli/jarvis/everything_tools.py's
    // reveal_in_explorer / open_file_location / open_file), so the actual
    // Explorer/OS logic lives in exactly one place.
    void handleFileAction(const NetworkPacket &np);
    // Scans one line of the assistant's streaming reply for absolute
    // Windows paths and, for any that actually exist on this PC (checked
    // right here with QFileInfo — no need to round-trip through Everything
    // for that), remembers it for sendCollectedFileActions().
    void collectFileActionCandidates(const QString &line);
    // Flushes whatever collectFileActionCandidates gathered during the
    // just-finished ask turn to the phone as one askFileActions packet, so
    // it can offer Reveal/Open buttons under the reply — mirrors the web
    // UI's JARVIS_MEDIA-driven file action buttons, but sourced from the
    // reply text itself rather than requiring jarvis-cli to emit anything
    // new, since this plugin already sees every line of that reply anyway.
    void sendCollectedFileActions();

    QNetworkAccessManager m_nam;
    QWebSocket m_ws;
    QProcess m_node;
    bool m_startedNode = false;
    int m_runId = 0;
    int m_askId = 0;
    QString m_activeKind;
    QString m_conversationId;
    // (path, isFolder) pairs found in the current ask turn's reply so far —
    // reset at the start of every new ask, flushed at the end of it.
    QVector<QPair<QString, bool>> m_askFilePaths;

private Q_SLOTS:
    void onWsTextMessage(const QString &message);
    void onWsError();
};
