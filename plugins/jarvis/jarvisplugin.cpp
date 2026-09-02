/**
 * SPDX-FileCopyrightText: 2026 Jarvis KDE Connect integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "jarvisplugin.h"

#include <KPluginFactory>

#include <QAbstractSocket>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrlQuery>

#include <core/device.h>
#include <core/networkpacket.h>

#include "plugin_jarvis_debug.h"

namespace
{
const QStringList s_fallbackTools = {
    QStringLiteral("get_datetime"),
    QStringLiteral("get_battery"),
    QStringLiteral("get_wifi_info"),
    QStringLiteral("get_location"),
    QStringLiteral("get_system_info"),
    QStringLiteral("get_disk_usage"),
    QStringLiteral("get_memory_usage"),
    QStringLiteral("run_command"),
    QStringLiteral("run_chain"),
    QStringLiteral("create_command"),
    QStringLiteral("update_command"),
    QStringLiteral("take_screenshot"),
};

QStringList extraSearchDirs()
{
    QStringList dirs;
    const QString home = QDir::homePath();
    dirs << (home + QStringLiteral("/.local/bin"));
#ifdef Q_OS_WIN
    const QString localAppData = QDir::fromNativeSeparators(qEnvironmentVariable("LOCALAPPDATA"));
    const QString roaming = QDir::fromNativeSeparators(qEnvironmentVariable("APPDATA"));
    const auto addTree = [&](const QString &root) {
        QDir d(root);
        if (!d.exists()) {
            return;
        }
        for (const QString &name : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            dirs << d.filePath(name + QStringLiteral("/Scripts"));
            dirs << d.filePath(name);
        }
    };
    addTree(roaming + QStringLiteral("/Python"));
    addTree(localAppData + QStringLiteral("/Programs/Python"));
    addTree(localAppData + QStringLiteral("/Programs"));
#endif
    dirs.removeDuplicates();
    return dirs;
}

QString findOnPath(const QString &name)
{
    QString found = QStandardPaths::findExecutable(name, extraSearchDirs());
    if (found.isEmpty()) {
        found = QStandardPaths::findExecutable(name);
    }
    if (found.contains(QStringLiteral("WindowsApps"), Qt::CaseInsensitive)) {
        return {};
    }
    return found;
}

QString encodePathSegment(const QString &name)
{
    return QString::fromUtf8(QUrl::toPercentEncoding(name));
}
}

K_PLUGIN_CLASS_WITH_JSON(JarvisPlugin, "kdeconnect_jarvis.json")

JarvisPlugin::JarvisPlugin(QObject *parent, const QVariantList &args)
    : KdeConnectPlugin(parent, args)
{
    connect(&m_ws, &QWebSocket::textMessageReceived, this, &JarvisPlugin::onWsTextMessage);
    connect(&m_ws, &QWebSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        onWsError();
    });
}

JarvisPlugin::~JarvisPlugin()
{
    handleCancel();
    m_ws.close();
    if (m_startedNode && m_node.state() != QProcess::NotRunning) {
        m_node.terminate();
    }
}

QUrl JarvisPlugin::baseUrl() const
{
    const QString override = qEnvironmentVariable("JARVIS_WEB_URL");
    if (!override.isEmpty()) {
        return QUrl(override);
    }
    return QUrl(QStringLiteral("http://127.0.0.1:4173"));
}

QUrl JarvisPlugin::wsUrl() const
{
    QUrl url = baseUrl();
    url.setScheme(url.scheme() == QLatin1String("https") ? QStringLiteral("wss") : QStringLiteral("ws"));
    url.setPath(QStringLiteral("/ws"));
    return url;
}

bool JarvisPlugin::pingServer(QString *error)
{
    QByteArray response;
    int status = 0;
    if (!http("GET", QStringLiteral("/api/status"), {}, &response, &status, 4000)) {
        if (error) {
            *error = QStringLiteral(
                "Jarvis web UI is not running on this PC (http://127.0.0.1:4173). Start it with npm start in jarvis/web, or set JARVIS_WEB to that folder.");
        }
        return false;
    }
    const QJsonObject obj = QJsonDocument::fromJson(response).object();
    if (!obj.value(QStringLiteral("online")).toBool()) {
        if (error) {
            *error = QStringLiteral("Jarvis web UI is up, but the CLI is not linked. Install jarvis and reload the web UI.");
        }
        return false;
    }
    return true;
}

void JarvisPlugin::tryStartNode()
{
    if (m_node.state() != QProcess::NotRunning) {
        return;
    }
    QString dir = qEnvironmentVariable("JARVIS_WEB");
    if (dir.isEmpty()) {
        dir = QDir::home().filePath(QStringLiteral(".jarvis/web"));
    }
    const QString serverJs = QDir(dir).filePath(QStringLiteral("server.js"));
    if (!QFile::exists(serverJs)) {
        return;
    }
    const QString node = findOnPath(QStringLiteral("node"));
    if (node.isEmpty()) {
        qCWarning(KDECONNECT_PLUGIN_JARVIS) << "Found server.js but no node executable";
        return;
    }
    m_node.setWorkingDirectory(dir);
    m_node.setProcessChannelMode(QProcess::SeparateChannels);
    m_node.start(node, {serverJs});
    if (m_node.waitForStarted(3000)) {
        m_startedNode = true;
        m_node.waitForFinished(1500); // returns false if still running — that's success
        if (m_node.state() == QProcess::NotRunning) {
            m_startedNode = false;
            qCWarning(KDECONNECT_PLUGIN_JARVIS) << "node server.js exited immediately" << m_node.readAllStandardError();
        }
    }
}

bool JarvisPlugin::ensureServer()
{
    QString error;
    if (pingServer(&error)) {
        return true;
    }
    tryStartNode();
    QEventLoop loop;
    QTimer::singleShot(1200, &loop, &QEventLoop::quit);
    loop.exec();
    return pingServer(&error);
}

bool JarvisPlugin::http(const QByteArray &method, const QString &path, const QByteArray &body, QByteArray *response, int *status, int timeoutMs)
{
    QUrl url = baseUrl();
    url.setPath(path);
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_nam.sendCustomRequest(req, method, body);
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
    timer.start(timeoutMs);
    loop.exec();
    if (!reply->isFinished()) {
        reply->abort();
        reply->deleteLater();
        return false;
    }
    if (status) {
        *status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    }
    if (response) {
        *response = reply->readAll();
    }
    const bool ok = reply->error() == QNetworkReply::NoError || (status && *status >= 200 && *status < 500);
    reply->deleteLater();
    return ok && status && *status >= 200 && *status < 300;
}

QJsonDocument JarvisPlugin::httpJson(const QByteArray &method, const QString &path, const QJsonValue &body, int *status, QString *error)
{
    QByteArray payload;
    if (!body.isUndefined() && !body.isNull()) {
        if (body.isObject()) {
            payload = QJsonDocument(body.toObject()).toJson(QJsonDocument::Compact);
        } else if (body.isArray()) {
            payload = QJsonDocument(body.toArray()).toJson(QJsonDocument::Compact);
        }
    }
    QByteArray response;
    int st = 0;
    if (!http(method, path, payload, &response, &st)) {
        const QJsonObject errObj = QJsonDocument::fromJson(response).object();
        if (error) {
            *error = errObj.value(QStringLiteral("error")).toString();
            if (error->isEmpty()) {
                *error = QStringLiteral("Request to Jarvis web UI failed.");
            }
        }
        if (status) {
            *status = st;
        }
        return {};
    }
    if (status) {
        *status = st;
    }
    return QJsonDocument::fromJson(response);
}

void JarvisPlugin::ensureWs()
{
    if (m_ws.state() == QAbstractSocket::ConnectedState) {
        return;
    }
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    connect(&m_ws, &QWebSocket::connected, &loop, &QEventLoop::quit);
    connect(&m_ws, &QWebSocket::errorOccurred, &loop, &QEventLoop::quit);
    connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
    m_ws.open(wsUrl());
    timer.start(4000);
    loop.exec();
}

void JarvisPlugin::connected()
{
    ensureServer();
    refreshToolCatalog();
    QString error;
    if (!pingServer(&error)) {
        sendStatus(error);
    } else {
        sendStatus();
    }
    sendCommands();
}

void JarvisPlugin::receivePacket(const NetworkPacket &np)
{
    const QString action = np.get<QString>(QStringLiteral("action"));
    if (action == QLatin1String("listCommands") || action == QLatin1String("requestStatus")) {
        ensureServer();
        QString error;
        if (!pingServer(&error)) {
            sendStatus(error);
        } else {
            sendStatus();
        }
        sendCommands();
        refreshToolCatalog();
        return;
    }
    if (action == QLatin1String("createCommand")) {
        handleCreateCommand(np);
        return;
    }
    if (action == QLatin1String("updateCommand")) {
        handleUpdateCommand(np);
        return;
    }
    if (action == QLatin1String("deleteCommand")) {
        handleDeleteCommand(np);
        return;
    }
    if (action == QLatin1String("getConfig")) {
        handleGetConfig(np);
        return;
    }
    if (action == QLatin1String("setConfig")) {
        handleSetConfig(np);
        return;
    }
    if (action == QLatin1String("run")) {
        handleRun(np);
        return;
    }
    if (action == QLatin1String("ask")) {
        handleAsk(np);
        return;
    }
    if (action == QLatin1String("cancel")) {
        handleCancel(np.get<QString>(QStringLiteral("kind")));
        return;
    }
    if (action == QLatin1String("aiClear")) {
        handleAiClear();
        return;
    }
}

void JarvisPlugin::sendStatus(const QString &error)
{
    QByteArray response;
    int status = 0;
    http("GET", QStringLiteral("/api/status"), {}, &response, &status, 4000);
    const QJsonObject obj = QJsonDocument::fromJson(response).object();
    const bool online = obj.value(QStringLiteral("online")).toBool() && error.isEmpty();
    sendPacketType(QStringLiteral("status"),
                   {
                       {QStringLiteral("online"), online},
                       {QStringLiteral("error"), error},
                       {QStringLiteral("configPath"), obj.value(QStringLiteral("configPath")).toString()},
                   });
}

void JarvisPlugin::sendCommands()
{
    int status = 0;
    QString error;
    const QJsonDocument doc = httpJson("GET", QStringLiteral("/api/commands"), {}, &status, &error);
    QString json = QStringLiteral("{}");
    if (doc.isObject()) {
        json = QString::fromUtf8(doc.toJson(QJsonDocument::Compact));
    }
    sendPacketType(QStringLiteral("commands"),
                   {
                       {QStringLiteral("commandsJson"), json},
                       {QStringLiteral("error"), error},
                   });
}

void JarvisPlugin::sendPacketType(const QString &type, const QVariantMap &extra)
{
    QVariantMap body = extra;
    body.insert(QStringLiteral("type"), type);
    NetworkPacket np(PACKET_TYPE_JARVIS, body);
    sendPacket(np);
}

void JarvisPlugin::refreshToolCatalog()
{
    int status = 0;
    QString error;
    const QJsonDocument doc = httpJson("GET", QStringLiteral("/api/tools"), {}, &status, &error);
    QJsonArray catalog = doc.isArray() ? doc.array() : QJsonArray();
    if (catalog.isEmpty()) {
        for (const QString &name : s_fallbackTools) {
            QJsonObject item;
            item.insert(QStringLiteral("name"), name);
            catalog.append(item);
        }
    }
    const QString compact = QString::fromUtf8(QJsonDocument(catalog).toJson(QJsonDocument::Compact));
    if (config()->getString(QStringLiteral("toolCatalog"), QString()) != compact) {
        config()->set(QStringLiteral("toolCatalog"), compact);
    }
}

QString JarvisPlugin::allowedToolsEnv() const
{
    const QJsonObject allowed = QJsonDocument::fromJson(config()->getByteArray(QStringLiteral("allowedTools"), "{}")).object();
    QStringList names;
    for (auto it = allowed.begin(); it != allowed.end(); ++it) {
        if (it.value().toBool()) {
            names.append(it.key());
        }
    }
    return names.join(QLatin1Char(','));
}

QString JarvisPlugin::configApiPath(const QString &which) const
{
    if (which == QLatin1String("commands")) {
        return QStringLiteral("/api/raw");
    }
    if (which == QLatin1String("ai")) {
        return QStringLiteral("/api/ai/raw");
    }
    if (which == QLatin1String("playnite")) {
        return QStringLiteral("/api/playnite/raw");
    }
    if (which == QLatin1String("spotify")) {
        return QStringLiteral("/api/spotify/raw");
    }
    if (which == QLatin1String("memory")) {
        return QStringLiteral("/api/memory/raw");
    }
    return {};
}

void JarvisPlugin::handleCreateCommand(const NetworkPacket &np)
{
    QJsonObject spec = QJsonDocument::fromJson(np.get<QString>(QStringLiteral("specJson")).toUtf8()).object();
    QJsonObject body;
    body.insert(QStringLiteral("name"), np.get<QString>(QStringLiteral("name")));
    body.insert(QStringLiteral("spec"), spec);
    int status = 0;
    QString error;
    httpJson("POST", QStringLiteral("/api/commands"), body, &status, &error);
    if (!error.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("createCommand")}});
    sendCommands();
}

void JarvisPlugin::handleUpdateCommand(const NetworkPacket &np)
{
    const QString name = np.get<QString>(QStringLiteral("name"));
    QString newName = np.get<QString>(QStringLiteral("newName"));
    if (newName.isEmpty()) {
        newName = name;
    }
    QJsonObject spec = QJsonDocument::fromJson(np.get<QString>(QStringLiteral("specJson")).toUtf8()).object();
    QJsonObject body;
    body.insert(QStringLiteral("name"), newName);
    body.insert(QStringLiteral("spec"), spec);
    int status = 0;
    QString error;
    httpJson("PUT", QStringLiteral("/api/commands/") + encodePathSegment(name), body, &status, &error);
    if (!error.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("updateCommand")}});
    sendCommands();
}

void JarvisPlugin::handleDeleteCommand(const NetworkPacket &np)
{
    const QString name = np.get<QString>(QStringLiteral("name"));
    int status = 0;
    QString error;
    httpJson("DELETE", QStringLiteral("/api/commands/") + encodePathSegment(name), {}, &status, &error);
    if (!error.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("deleteCommand")}});
    sendCommands();
}

void JarvisPlugin::handleGetConfig(const NetworkPacket &np)
{
    const QString which = np.get<QString>(QStringLiteral("which"));
    const QString path = configApiPath(which);
    if (path.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Unknown config.")}});
        return;
    }
    int status = 0;
    QString error;
    const QJsonDocument doc = httpJson("GET", path, {}, &status, &error);
    const QJsonObject obj = doc.object();
    sendPacketType(QStringLiteral("config"),
                   {
                       {QStringLiteral("which"), which},
                       {QStringLiteral("path"), obj.value(QStringLiteral("path")).toString()},
                       {QStringLiteral("text"), obj.value(QStringLiteral("text")).toString()},
                       {QStringLiteral("error"), error},
                   });
}

void JarvisPlugin::handleSetConfig(const NetworkPacket &np)
{
    const QString which = np.get<QString>(QStringLiteral("which"));
    const QString path = configApiPath(which);
    QJsonObject body;
    body.insert(QStringLiteral("text"), np.get<QString>(QStringLiteral("text")));
    int status = 0;
    QString error;
    httpJson("PUT", path, body, &status, &error);
    if (!error.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("setConfig")}, {QStringLiteral("which"), which}});
    if (which == QLatin1String("commands")) {
        sendCommands();
    }
}

void JarvisPlugin::handleRun(const NetworkPacket &np)
{
    if (!ensureServer()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Jarvis web UI is not running.")}});
        return;
    }
    ensureWs();
    if (m_ws.state() != QAbstractSocket::ConnectedState) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Couldn't open Jarvis web socket.")}});
        return;
    }
    m_runId = static_cast<int>(np.get<qlonglong>(QStringLiteral("id")));
    m_activeKind = QStringLiteral("run");
    const QJsonArray segments = QJsonDocument::fromJson(np.get<QString>(QStringLiteral("segmentsJson")).toUtf8()).array();
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("run"));
    msg.insert(QStringLiteral("segments"), segments);
    m_ws.sendTextMessage(QString::fromUtf8(QJsonDocument(msg).toJson(QJsonDocument::Compact)));
}

void JarvisPlugin::handleAsk(const NetworkPacket &np)
{
    if (!ensureServer()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Jarvis web UI is not running.")}});
        return;
    }
    ensureWs();
    if (m_ws.state() != QAbstractSocket::ConnectedState) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Couldn't open Jarvis web socket.")}});
        return;
    }
    m_askId = static_cast<int>(np.get<qlonglong>(QStringLiteral("id")));
    m_activeKind = QStringLiteral("ask");
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("ask"));
    msg.insert(QStringLiteral("text"), np.get<QString>(QStringLiteral("text")));
    msg.insert(QStringLiteral("allowedTools"), allowedToolsEnv());
    m_ws.sendTextMessage(QString::fromUtf8(QJsonDocument(msg).toJson(QJsonDocument::Compact)));
}

void JarvisPlugin::handleCancel(const QString &kind)
{
    if (m_ws.state() != QAbstractSocket::ConnectedState) {
        return;
    }
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("cancel"));
    if (kind == QLatin1String("ask") || kind == QLatin1String("run")) {
        msg.insert(QStringLiteral("kind"), kind);
    }
    m_ws.sendTextMessage(QString::fromUtf8(QJsonDocument(msg).toJson(QJsonDocument::Compact)));
}

void JarvisPlugin::handleAiClear()
{
    int status = 0;
    QString error;
    httpJson("POST", QStringLiteral("/api/ai/clear"), QJsonObject(), &status, &error);
    if (!error.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("aiClear")}});
}

void JarvisPlugin::fetchScreenshot(const QString &filename)
{
    static const QRegularExpression valid(QStringLiteral("^ss_[A-Za-z0-9_.-]+\\.png$"));
    if (!valid.match(filename).hasMatch()) {
        return;
    }
    QByteArray response;
    int status = 0;
    if (!http("GET", QStringLiteral("/api/screenshots/") + filename, {}, &response, &status, 20000) || response.isEmpty()) {
        return;
    }
    sendPacketType(QStringLiteral("screenshot"),
                   {
                       {QStringLiteral("filename"), filename},
                       {QStringLiteral("data"), QString::fromLatin1(response.toBase64())},
                   });
}

void JarvisPlugin::onWsTextMessage(const QString &message)
{
    const QJsonObject obj = QJsonDocument::fromJson(message.toUtf8()).object();
    const QString type = obj.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("commands")) {
        sendCommands();
        return;
    }
    if (type == QLatin1String("start")) {
        sendPacketType(QStringLiteral("runStart"),
                       {
                           {QStringLiteral("id"), m_runId},
                           {QStringLiteral("cmdline"), obj.value(QStringLiteral("cmdline")).toString()},
                       });
        return;
    }
    if (type == QLatin1String("stdout")) {
        sendPacketType(QStringLiteral("runStdout"), {{QStringLiteral("id"), m_runId}, {QStringLiteral("line"), obj.value(QStringLiteral("line")).toString()}});
        return;
    }
    if (type == QLatin1String("stderr")) {
        sendPacketType(QStringLiteral("runStderr"), {{QStringLiteral("id"), m_runId}, {QStringLiteral("line"), obj.value(QStringLiteral("line")).toString()}});
        return;
    }
    if (type == QLatin1String("exit")) {
        sendPacketType(QStringLiteral("runExit"), {{QStringLiteral("id"), m_runId}, {QStringLiteral("code"), obj.value(QStringLiteral("code")).toInt()}});
        return;
    }
    if (type == QLatin1String("error")) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), obj.value(QStringLiteral("message")).toString()}});
        return;
    }
    if (type == QLatin1String("ask-start")) {
        sendPacketType(QStringLiteral("askStart"), {{QStringLiteral("id"), m_askId}});
        return;
    }
    if (type == QLatin1String("ask-stdout")) {
        sendPacketType(QStringLiteral("askStdout"), {{QStringLiteral("id"), m_askId}, {QStringLiteral("line"), obj.value(QStringLiteral("line")).toString()}});
        return;
    }
    if (type == QLatin1String("ask-stderr")) {
        const QString line = obj.value(QStringLiteral("line")).toString();
        if (line.startsWith(QLatin1String("JARVIS_MEDIA\t"))) {
            const QStringList parts = line.split(QLatin1Char('\t'));
            if (parts.size() >= 3 && parts.at(1) == QLatin1String("screenshot")) {
                fetchScreenshot(parts.at(2).trimmed());
            }
        }
        sendPacketType(QStringLiteral("askStderr"), {{QStringLiteral("id"), m_askId}, {QStringLiteral("line"), line}});
        return;
    }
    if (type == QLatin1String("ask-exit") || type == QLatin1String("ask-error")) {
        if (type == QLatin1String("ask-error")) {
            sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), obj.value(QStringLiteral("message")).toString()}});
        }
        sendPacketType(QStringLiteral("askExit"), {{QStringLiteral("id"), m_askId}, {QStringLiteral("code"), obj.value(QStringLiteral("code")).toInt()}});
    }
}

void JarvisPlugin::onWsError()
{
    qCWarning(KDECONNECT_PLUGIN_JARVIS) << "Jarvis websocket error" << m_ws.errorString();
}

#include "moc_jarvisplugin.cpp"
#include "jarvisplugin.moc"
