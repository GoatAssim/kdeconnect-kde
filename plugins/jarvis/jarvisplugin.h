/**
 * SPDX-FileCopyrightText: 2026 Jarvis KDE Connect integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#pragma once

#include <QByteArray>
#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QPointer>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QTimer>

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
    struct Invoker {
        QString program;
        QStringList prefixArgs;
        QString configPath;
    };

    void resolveJarvis();
    bool runJarvisOnce(const QStringList &args, QString *stdoutText, QString *stderrText, int timeoutMs = 8000);
    QString configPathFor(const QString &which);
    QString allowedToolsEnv() const;
    void refreshToolCatalog();
    void sendStatus(const QString &error = {});
    void sendCommands();
    void sendPacketType(const QString &type, const QVariantMap &extra = {});
    void handleListCommands();
    void handleCreateCommand(const NetworkPacket &np);
    void handleUpdateCommand(const NetworkPacket &np);
    void handleDeleteCommand(const NetworkPacket &np);
    void handleGetConfig(const NetworkPacket &np);
    void handleSetConfig(const NetworkPacket &np);
    void handleRun(const NetworkPacket &np);
    void handleAsk(const NetworkPacket &np);
    void handleCancel();
    void handleAiClear();
    void spawnStreaming(const QString &kind, int id, const QStringList &args, bool applyToolAllowlist);
    void onStreamReadyRead(bool isStderr);
    void onStreamFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void watchCommandsFile();
    QJsonObject readCommandsObject(QString *error) const;
    bool writeCommandsObject(const QJsonObject &commands, QString *error);

    Invoker m_invoker;
    bool m_resolved = false;
    QPointer<QProcess> m_active;
    QString m_activeKind;
    int m_activeId = 0;
    QByteArray m_stdoutBuf;
    QByteArray m_stderrBuf;
    QFileSystemWatcher m_watcher;
    QTimer m_watchDebounce;
    qint64 m_suppressWatchUntil = 0;
};
