/**
 * SPDX-FileCopyrightText: 2026 Jarvis KDE Connect integration
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "jarvisplugin.h"

#include <KPluginFactory>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>

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
    QStringLiteral("memory_save"),
    QStringLiteral("memory_forget"),
    QStringLiteral("memory_search"),
    QStringLiteral("radio_status"),
    QStringLiteral("wifi_set"),
    QStringLiteral("bluetooth_set"),
    QStringLiteral("git_run"),
    QStringLiteral("take_screenshot"),
    QStringLiteral("web_search"),
    QStringLiteral("web_fetch"),
    QStringLiteral("package_managers"),
    QStringLiteral("package_search"),
    QStringLiteral("package_info"),
    QStringLiteral("package_list"),
    QStringLiteral("package_install"),
    QStringLiteral("package_uninstall"),
    QStringLiteral("spotify_open"),
    QStringLiteral("spotify_now"),
    QStringLiteral("spotify_search"),
    QStringLiteral("spotify_play"),
    QStringLiteral("spotify_control"),
    QStringLiteral("spotify_queue"),
    QStringLiteral("spotify_playlists"),
    QStringLiteral("spotify_suggest"),
    QStringLiteral("spotify_like"),
    QStringLiteral("playnite_list_game_actions"),
    QStringLiteral("playnite_launch_action"),
    QStringLiteral("playnite_find_game"),
    QStringLiteral("playnite_launch_game"),
    QStringLiteral("playnite_library_stats"),
    QStringLiteral("playnite_get_game"),
    QStringLiteral("playnite_update_game"),
    QStringLiteral("playnite_list_frequent"),
    QStringLiteral("playnite_delete_game"),
    QStringLiteral("playnite_get_action"),
    QStringLiteral("playnite_install_game"),
    QStringLiteral("playnite_uninstall_game"),
    QStringLiteral("playnite_manage_game_lists"),
    QStringLiteral("playnite_fetch_game_art"),
    QStringLiteral("playnite_list_missing_art"),
    QStringLiteral("playnite_query_games"),
    QStringLiteral("playnite_list_collections"),
    QStringLiteral("playnite_create_collection"),
    QStringLiteral("playnite_view"),
    QStringLiteral("playnite_app_info"),
    QStringLiteral("playnite_list_addons"),
    QStringLiteral("playnite_list_plugins"),
    QStringLiteral("playnite_notify"),
    QStringLiteral("playnite_auto_categorize"),
    QStringLiteral("playnite_fetch_all_art"),
    QStringLiteral("playnite_get_achievements"),
    QStringLiteral("playnite_get_activity"),
    QStringLiteral("playnite_get_cover"),
    QStringLiteral("playnite_eval"),
    QStringLiteral("playnite_rotate_token"),
    QStringLiteral("playnite_get_skill"),
};

QStringList splitLines(QByteArray *buffer, const QByteArray &chunk, bool flush)
{
    buffer->append(chunk);
    QStringList lines;
    int idx;
    while ((idx = buffer->indexOf('\n')) >= 0) {
        QByteArray line = buffer->left(idx);
        buffer->remove(0, idx + 1);
        if (line.endsWith('\r')) {
            line.chop(1);
        }
        lines.append(QString::fromUtf8(line));
    }
    if (flush && !buffer->isEmpty()) {
        QByteArray line = *buffer;
        buffer->clear();
        if (line.endsWith('\r')) {
            line.chop(1);
        }
        lines.append(QString::fromUtf8(line));
    }
    return lines;
}

QJsonObject parseObject(const QString &text, QString *error)
{
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(text.toUtf8(), &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        if (error) {
            *error = pe.error != QJsonParseError::NoError ? pe.errorString() : QStringLiteral("Top-level JSON must be an object.");
        }
        return {};
    }
    return doc.object();
}

bool validCommandName(const QString &name, QString *error)
{
    static const QSet<QString> reserved = {
        QStringLiteral("config"),
        QStringLiteral("ai-config"),
        QStringLiteral("ai-clear"),
        QStringLiteral("ai-drop-from"),
        QStringLiteral("playnite-config"),
        QStringLiteral("spotify-config"),
        QStringLiteral("spotify-login"),
        QStringLiteral("memory-config"),
        QStringLiteral("tools-list"),
        QStringLiteral("then"),
        QStringLiteral("and"),
        QStringLiteral("-h"),
        QStringLiteral("--help"),
    };
    if (name.trimmed().isEmpty()) {
        *error = QStringLiteral("Command name can't be empty.");
        return false;
    }
    if (name.contains(QRegularExpression(QStringLiteral("\\s")))) {
        *error = QStringLiteral("Command name can't contain spaces.");
        return false;
    }
    if (reserved.contains(name)) {
        *error = QStringLiteral("That name is reserved by jarvis.");
        return false;
    }
    return true;
}
}

K_PLUGIN_CLASS_WITH_JSON(JarvisPlugin, "kdeconnect_jarvis.json")

JarvisPlugin::JarvisPlugin(QObject *parent, const QVariantList &args)
    : KdeConnectPlugin(parent, args)
{
    m_watchDebounce.setSingleShot(true);
    m_watchDebounce.setInterval(200);
    connect(&m_watchDebounce, &QTimer::timeout, this, &JarvisPlugin::sendCommands);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
        if (!m_watcher.files().contains(path) && QFile::exists(path)) {
            m_watcher.addPath(path);
        }
        if (QDateTime::currentMSecsSinceEpoch() < m_suppressWatchUntil) {
            return;
        }
        m_watchDebounce.start();
    });
}

JarvisPlugin::~JarvisPlugin()
{
    handleCancel();
}

void JarvisPlugin::connected()
{
    resolveJarvis();
    refreshToolCatalog();
    if (m_invoker.program.isEmpty()) {
        sendStatus(QStringLiteral("Couldn't find the jarvis CLI. kdeconnectd may not see the same PATH as your terminal. Set JARVIS_BIN to the full command, or install jarvis on PATH."));
    } else {
        sendStatus();
    }
    sendCommands();
    watchCommandsFile();
}

void JarvisPlugin::receivePacket(const NetworkPacket &np)
{
    const QString action = np.get<QString>(QStringLiteral("action"));
    if (action == QLatin1String("listCommands") || action == QLatin1String("requestStatus")) {
        resolveJarvis();
        sendStatus();
        sendCommands();
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
        handleCancel();
        return;
    }
    if (action == QLatin1String("aiClear")) {
        handleAiClear();
        return;
    }
}

void JarvisPlugin::resolveJarvis()
{
    if (m_resolved && !m_invoker.program.isEmpty()) {
        return;
    }

    QList<Invoker> candidates;
    const QString override = qEnvironmentVariable("JARVIS_BIN");
    if (!override.isEmpty()) {
        const QStringList parts = QProcess::splitCommand(override);
        if (!parts.isEmpty()) {
            Invoker inv;
            inv.program = parts.first();
            inv.prefixArgs = parts.mid(1);
            candidates.append(inv);
        }
    }
    candidates.append(Invoker{QStringLiteral("jarvis"), {}, {}});
    candidates.append(Invoker{QStringLiteral("python"), {QStringLiteral("-m"), QStringLiteral("jarvis")}, {}});
    candidates.append(Invoker{QStringLiteral("python3"), {QStringLiteral("-m"), QStringLiteral("jarvis")}, {}});
    candidates.append(Invoker{QStringLiteral("py"), {QStringLiteral("-m"), QStringLiteral("jarvis")}, {}});

    for (Invoker cand : candidates) {
        QString out;
        QString err;
        Invoker saved = m_invoker;
        m_invoker = cand;
        m_resolved = true;
        if (runJarvisOnce({QStringLiteral("config")}, &out, &err, 2500) && !out.trimmed().isEmpty()) {
            m_invoker.configPath = out.trimmed().split(QLatin1Char('\n')).last().trimmed();
            qCDebug(KDECONNECT_PLUGIN_JARVIS) << "Linked jarvis" << m_invoker.program << m_invoker.prefixArgs << m_invoker.configPath;
            return;
        }
        m_invoker = saved;
        m_resolved = false;
    }
    qCWarning(KDECONNECT_PLUGIN_JARVIS) << "Could not find the jarvis CLI";
}

bool JarvisPlugin::runJarvisOnce(const QStringList &args, QString *stdoutText, QString *stderrText, int timeoutMs)
{
    if (m_invoker.program.isEmpty()) {
        if (stdoutText) {
            stdoutText->clear();
        }
        if (stderrText) {
            *stderrText = QStringLiteral("jarvis CLI is not connected.");
        }
        return false;
    }
    QProcess proc;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("PYTHONUNBUFFERED"), QStringLiteral("1"));
    env.insert(QStringLiteral("PYTHONIOENCODING"), QStringLiteral("utf-8"));
    proc.setProcessEnvironment(env);
    proc.setProcessChannelMode(QProcess::SeparateChannels);
    proc.start(m_invoker.program, QStringList() << m_invoker.prefixArgs << args);
    if (!proc.waitForStarted(timeoutMs)) {
        if (stderrText) {
            *stderrText = proc.errorString();
        }
        return false;
    }
    if (!proc.waitForFinished(timeoutMs)) {
        proc.kill();
        proc.waitForFinished(1000);
        if (stderrText) {
            *stderrText = QStringLiteral("timed out");
        }
        return false;
    }
    if (stdoutText) {
        *stdoutText = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    }
    if (stderrText) {
        *stderrText = QString::fromUtf8(proc.readAllStandardError()).trimmed();
    }
    return proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
}

QString JarvisPlugin::configPathFor(const QString &which)
{
    resolveJarvis();
    QString flag;
    if (which == QLatin1String("commands")) {
        return m_invoker.configPath;
    }
    if (which == QLatin1String("ai")) {
        flag = QStringLiteral("ai-config");
    } else if (which == QLatin1String("playnite")) {
        flag = QStringLiteral("playnite-config");
    } else if (which == QLatin1String("spotify")) {
        flag = QStringLiteral("spotify-config");
    } else if (which == QLatin1String("memory")) {
        flag = QStringLiteral("memory-config");
    } else {
        return {};
    }
    QString out;
    QString err;
    if (!runJarvisOnce({flag}, &out, &err) || out.isEmpty()) {
        return {};
    }
    return out.split(QLatin1Char('\n')).last().trimmed();
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

void JarvisPlugin::refreshToolCatalog()
{
    resolveJarvis();
    QJsonArray catalog;
    QString out;
    QString err;
    if (runJarvisOnce({QStringLiteral("tools-list")}, &out, &err, 6000)) {
        const QJsonDocument doc = QJsonDocument::fromJson(out.toUtf8());
        if (doc.isArray()) {
            catalog = doc.array();
        }
    }
    if (catalog.isEmpty()) {
        for (const QString &name : s_fallbackTools) {
            QJsonObject item;
            item.insert(QStringLiteral("name"), name);
            item.insert(QStringLiteral("description"), QString());
            catalog.append(item);
        }
    }
    const QString compact = QString::fromUtf8(QJsonDocument(catalog).toJson(QJsonDocument::Compact));
    if (config()->getString(QStringLiteral("toolCatalog"), QString()) != compact) {
        config()->set(QStringLiteral("toolCatalog"), compact);
    }
}

void JarvisPlugin::sendStatus(const QString &error)
{
    sendPacketType(QStringLiteral("status"),
                   {
                       {QStringLiteral("online"), !m_invoker.program.isEmpty() && !m_invoker.configPath.isEmpty()},
                       {QStringLiteral("error"), error},
                       {QStringLiteral("configPath"), m_invoker.configPath},
                   });
}

void JarvisPlugin::sendCommands()
{
    QString error;
    const QJsonObject commands = readCommandsObject(&error);
    sendPacketType(QStringLiteral("commands"),
                   {
                       {QStringLiteral("commandsJson"), QString::fromUtf8(QJsonDocument(commands).toJson(QJsonDocument::Compact))},
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

QJsonObject JarvisPlugin::readCommandsObject(QString *error) const
{
    if (m_invoker.configPath.isEmpty()) {
        if (error) {
            *error = QStringLiteral("jarvis CLI is not connected.");
        }
        return {};
    }
    QFile file(m_invoker.configPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (error) {
            *error = file.errorString();
        }
        return {};
    }
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        if (error) {
            *error = pe.errorString();
        }
        return {};
    }
    const QJsonValue commands = doc.object().value(QStringLiteral("commands"));
    if (!commands.isObject()) {
        return {};
    }
    return commands.toObject();
}

bool JarvisPlugin::writeCommandsObject(const QJsonObject &commands, QString *error)
{
    if (m_invoker.configPath.isEmpty()) {
        if (error) {
            *error = QStringLiteral("jarvis CLI is not connected.");
        }
        return false;
    }
    QFile file(m_invoker.configPath);
    QJsonObject root;
    if (file.exists() && file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) {
            root = doc.object();
        }
        file.close();
    }
    root.insert(QStringLiteral("commands"), commands);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        if (error) {
            *error = file.errorString();
        }
        return false;
    }
    m_suppressWatchUntil = QDateTime::currentMSecsSinceEpoch() + 400;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.close();
    sendCommands();
    return true;
}

void JarvisPlugin::watchCommandsFile()
{
    if (m_invoker.configPath.isEmpty()) {
        return;
    }
    const QStringList files = m_watcher.files();
    if (!files.isEmpty()) {
        m_watcher.removePaths(files);
    }
    m_watcher.addPath(m_invoker.configPath);
}

void JarvisPlugin::handleCreateCommand(const NetworkPacket &np)
{
    QString error;
    const QString name = np.get<QString>(QStringLiteral("name"));
    if (!validCommandName(name, &error)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    const QJsonObject spec = parseObject(np.get<QString>(QStringLiteral("specJson")), &error);
    if (!error.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    QJsonObject commands = readCommandsObject(&error);
    if (m_invoker.configPath.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("jarvis CLI is not connected.")}});
        return;
    }
    if (commands.contains(name)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("A command with that name already exists.")}});
        return;
    }
    commands.insert(name, spec);
    if (!writeCommandsObject(commands, &error)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("createCommand")}});
}

void JarvisPlugin::handleUpdateCommand(const NetworkPacket &np)
{
    QString error;
    const QString name = np.get<QString>(QStringLiteral("name"));
    QString newName = np.get<QString>(QStringLiteral("newName"));
    if (newName.isEmpty()) {
        newName = name;
    }
    if (!validCommandName(newName, &error)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    const QJsonObject spec = parseObject(np.get<QString>(QStringLiteral("specJson")), &error);
    if (!error.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    QJsonObject commands = readCommandsObject(&error);
    if (!commands.contains(name)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("No command with that name.")}});
        return;
    }
    if (newName != name && commands.contains(newName)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("A command with that name already exists.")}});
        return;
    }
    if (newName != name) {
        commands.remove(name);
    }
    commands.insert(newName, spec);
    if (!writeCommandsObject(commands, &error)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("updateCommand")}});
}

void JarvisPlugin::handleDeleteCommand(const NetworkPacket &np)
{
    QString error;
    const QString name = np.get<QString>(QStringLiteral("name"));
    QJsonObject commands = readCommandsObject(&error);
    if (!commands.contains(name)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("No command with that name.")}});
        return;
    }
    commands.remove(name);
    if (!writeCommandsObject(commands, &error)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), error}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("deleteCommand")}});
}

void JarvisPlugin::handleGetConfig(const NetworkPacket &np)
{
    const QString which = np.get<QString>(QStringLiteral("which"));
    const QString path = configPathFor(which);
    if (path.isEmpty()) {
        sendPacketType(QStringLiteral("config"),
                       {
                           {QStringLiteral("which"), which},
                           {QStringLiteral("error"), QStringLiteral("Couldn't locate that config file.")},
                       });
        return;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        sendPacketType(QStringLiteral("config"),
                       {
                           {QStringLiteral("which"), which},
                           {QStringLiteral("path"), path},
                           {QStringLiteral("error"), file.errorString()},
                       });
        return;
    }
    sendPacketType(QStringLiteral("config"),
                   {
                       {QStringLiteral("which"), which},
                       {QStringLiteral("path"), path},
                       {QStringLiteral("text"), QString::fromUtf8(file.readAll())},
                       {QStringLiteral("error"), QString()},
                   });
}

void JarvisPlugin::handleSetConfig(const NetworkPacket &np)
{
    const QString which = np.get<QString>(QStringLiteral("which"));
    const QString text = np.get<QString>(QStringLiteral("text"));
    QString parseError;
    const QJsonObject obj = parseObject(text, &parseError);
    if (!parseError.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), parseError}});
        return;
    }
    if (which == QLatin1String("commands") && !obj.value(QStringLiteral("commands")).isObject()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Top-level JSON must have a 'commands' object.")}});
        return;
    }
    if (which == QLatin1String("ai") && obj.contains(QStringLiteral("providers")) && !obj.value(QStringLiteral("providers")).isArray()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("'providers' must be an array.")}});
        return;
    }
    if (which == QLatin1String("memory") && obj.contains(QStringLiteral("facts")) && !obj.value(QStringLiteral("facts")).isArray()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("'facts' must be an array.")}});
        return;
    }
    const QString path = configPathFor(which);
    if (path.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Couldn't locate that config file.")}});
        return;
    }
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), file.errorString()}});
        return;
    }
    if (which == QLatin1String("commands")) {
        m_suppressWatchUntil = QDateTime::currentMSecsSinceEpoch() + 400;
    }
    QByteArray payload = text.toUtf8();
    if (!payload.endsWith('\n')) {
        payload.append('\n');
    }
    file.write(payload);
    file.close();
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("setConfig")}, {QStringLiteral("which"), which}});
    if (which == QLatin1String("commands")) {
        sendCommands();
    }
}

void JarvisPlugin::handleRun(const NetworkPacket &np)
{
    resolveJarvis();
    if (m_invoker.program.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("jarvis CLI is not connected.")}});
        return;
    }
    if (m_active) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Something is already running.")}});
        return;
    }
    const int id = static_cast<int>(np.get<qlonglong>(QStringLiteral("id")));
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(np.get<QString>(QStringLiteral("segmentsJson")).toUtf8(), &pe);
    if (!doc.isArray()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Nothing to run.")}});
        return;
    }
    QStringList argv;
    const QJsonArray segments = doc.array();
    if (segments.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Nothing to run.")}});
        return;
    }
    for (int i = 0; i < segments.size(); ++i) {
        const QJsonObject seg = segments.at(i).toObject();
        if (i > 0) {
            argv.append(seg.value(QStringLiteral("mode")).toString() == QLatin1String("and") ? QStringLiteral("and") : QStringLiteral("then"));
        }
        const QString name = seg.value(QStringLiteral("name")).toString();
        argv.append(name);
        const QJsonObject flags = seg.value(QStringLiteral("flags")).toObject();
        for (auto it = flags.begin(); it != flags.end(); ++it) {
            argv.append(QStringLiteral("--") + it.key());
            argv.append(it.value().toVariant().toString());
        }
    }
    spawnStreaming(QStringLiteral("run"), id, argv, false);
}

void JarvisPlugin::handleAsk(const NetworkPacket &np)
{
    resolveJarvis();
    if (m_invoker.program.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("jarvis CLI is not connected.")}});
        return;
    }
    if (m_active) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Something is already running.")}});
        return;
    }
    const int id = static_cast<int>(np.get<qlonglong>(QStringLiteral("id")));
    const QString text = np.get<QString>(QStringLiteral("text")).trimmed();
    if (text.isEmpty()) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), QStringLiteral("Nothing to ask.")}});
        return;
    }
    spawnStreaming(QStringLiteral("ask"), id, {text}, true);
}

void JarvisPlugin::handleCancel()
{
    if (!m_active) {
        return;
    }
#ifdef Q_OS_WIN
    m_active->kill();
#else
    m_active->terminate();
#endif
}

void JarvisPlugin::handleAiClear()
{
    QString out;
    QString err;
    if (!runJarvisOnce({QStringLiteral("ai-clear")}, &out, &err)) {
        sendPacketType(QStringLiteral("error"), {{QStringLiteral("message"), err.isEmpty() ? QStringLiteral("Couldn't clear history.") : err}});
        return;
    }
    sendPacketType(QStringLiteral("ok"), {{QStringLiteral("action"), QStringLiteral("aiClear")}, {QStringLiteral("message"), out}});
}

void JarvisPlugin::spawnStreaming(const QString &kind, int id, const QStringList &args, bool applyToolAllowlist)
{
    auto *process = new QProcess(this);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("PYTHONUNBUFFERED"), QStringLiteral("1"));
    env.insert(QStringLiteral("PYTHONIOENCODING"), QStringLiteral("utf-8"));
    if (applyToolAllowlist) {
        env.insert(QStringLiteral("JARVIS_ALLOWED_TOOLS"), allowedToolsEnv());
    }
    process->setProcessEnvironment(env);
    process->setProcessChannelMode(QProcess::SeparateChannels);

    m_active = process;
    m_activeKind = kind;
    m_activeId = id;
    m_stdoutBuf.clear();
    m_stderrBuf.clear();

    connect(process, &QProcess::readyReadStandardOutput, this, [this] {
        onStreamReadyRead(false);
    });
    connect(process, &QProcess::readyReadStandardError, this, [this] {
        onStreamReadyRead(true);
    });
    connect(process, &QProcess::finished, this, &JarvisPlugin::onStreamFinished);

    const QString startType = kind == QLatin1String("ask") ? QStringLiteral("askStart") : QStringLiteral("runStart");
    sendPacketType(startType,
                   {
                       {QStringLiteral("id"), id},
                       {QStringLiteral("cmdline"), (QStringList() << m_invoker.program << m_invoker.prefixArgs << args).join(QLatin1Char(' '))},
                   });
    process->start(m_invoker.program, QStringList() << m_invoker.prefixArgs << args);
}

void JarvisPlugin::onStreamReadyRead(bool isStderr)
{
    if (!m_active) {
        return;
    }
    const bool ask = m_activeKind == QLatin1String("ask");
    QByteArray *buf = isStderr ? &m_stderrBuf : &m_stdoutBuf;
    const QByteArray chunk = isStderr ? m_active->readAllStandardError() : m_active->readAllStandardOutput();
    const QStringList lines = splitLines(buf, chunk, false);
    const QString type = ask ? (isStderr ? QStringLiteral("askStderr") : QStringLiteral("askStdout"))
                             : (isStderr ? QStringLiteral("runStderr") : QStringLiteral("runStdout"));
    for (const QString &line : lines) {
        sendPacketType(type, {{QStringLiteral("id"), m_activeId}, {QStringLiteral("line"), line}});
    }
}

void JarvisPlugin::onStreamFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)
    if (m_active) {
        const bool ask = m_activeKind == QLatin1String("ask");
        for (const QString &line : splitLines(&m_stdoutBuf, {}, true)) {
            sendPacketType(ask ? QStringLiteral("askStdout") : QStringLiteral("runStdout"),
                           {{QStringLiteral("id"), m_activeId}, {QStringLiteral("line"), line}});
        }
        for (const QString &line : splitLines(&m_stderrBuf, {}, true)) {
            sendPacketType(ask ? QStringLiteral("askStderr") : QStringLiteral("runStderr"),
                           {{QStringLiteral("id"), m_activeId}, {QStringLiteral("line"), line}});
        }
        sendPacketType(ask ? QStringLiteral("askExit") : QStringLiteral("runExit"),
                       {{QStringLiteral("id"), m_activeId}, {QStringLiteral("code"), exitCode}});
        m_active->deleteLater();
        m_active = nullptr;
    }
    m_activeKind.clear();
    m_activeId = 0;
}

#include "moc_jarvisplugin.cpp"
#include "jarvisplugin.moc"
