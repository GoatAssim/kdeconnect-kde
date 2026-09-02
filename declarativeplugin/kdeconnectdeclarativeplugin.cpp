/**
 * SPDX-FileCopyrightText: 2013 Albert Vaca <albertvaka@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "kdeconnectdeclarativeplugin.h"

#include <QDBusPendingCall>
#include <QDBusPendingReply>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <devicespluginfilterproxymodel.h>

#include "dbusinterfaces.h"
#include "objectfactory.h"
#include "responsewaiter.h"

QObject *createDBusResponse()
{
    return new DBusAsyncResponse();
}

static QObject *createShizukuInterface(const QVariant &deviceId)
{
    return new ShizukuDbusInterface(deviceId.toString());
}

static QObject *createTailscaleInterface(const QVariant &deviceId)
{
    return new TailscaleDbusInterface(deviceId.toString());
}
static QObject *createCallBridgeInterface(const QVariant &deviceId)
{
    return new CallBridgeDbusInterface(deviceId.toString());
}
void KdeConnectDeclarativePlugin::registerTypes(const char * /*uri*/)
{
}

void KdeConnectDeclarativePlugin::initializeEngine(QQmlEngine *engine, const char *uri)
{
    QQmlExtensionPlugin::initializeEngine(engine, uri);

    engine->rootContext()->setContextProperty(QStringLiteral("DBusResponseFactory"), new ObjectFactory(engine, createDBusResponse));

    engine->rootContext()->setContextProperty(QStringLiteral("DBusResponseWaiter"), DBusResponseWaiter::instance());

    // Make Shizuku / Tailscale visible to QML the same way
    engine->rootContext()->setContextProperty(QStringLiteral("ShizukuDbusInterfaceFactory"), new ObjectFactory(engine, createShizukuInterface));
    engine->rootContext()->setContextProperty(QStringLiteral("CallBridgeDbusInterfaceFactory"), new ObjectFactory(engine, createCallBridgeInterface));
    engine->rootContext()->setContextProperty(QStringLiteral("TailscaleDbusInterfaceFactory"), new ObjectFactory(engine, createTailscaleInterface));
}

#include "moc_kdeconnectdeclarativeplugin.cpp"
