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

#include "objectfactory.h"
#include "responsewaiter.h"

#include "dbusinterfaces.h"

QObject *createDBusResponse()
{
    return new DBusAsyncResponse();
}

template<typename T>
void registerFactory(const char *uri, const char *name)
{
    qmlRegisterSingletonType<ObjectFactory>(uri, 1, 0, name, [](QQmlEngine *engine, QJSEngine *) -> QObject * {
        return new ObjectFactory(engine, [](const QVariant &deviceId) -> QObject * {
            return new T(deviceId.toString());
        });
    });
}

void KdeConnectDeclarativePlugin::registerTypes(const char *uri)
{
    registerFactory<ShizukuDbusInterface>(uri, "ShizukuDbusInterfaceFactory");
    registerFactory<TailscaleDbusInterface>(uri, "TailscaleDbusInterfaceFactory");
}

void KdeConnectDeclarativePlugin::initializeEngine(QQmlEngine *engine, const char *uri)
{
    QQmlExtensionPlugin::initializeEngine(engine, uri);

    engine->rootContext()->setContextProperty(QStringLiteral("DBusResponseFactory"), new ObjectFactory(engine, createDBusResponse));
    engine->rootContext()->setContextProperty(QStringLiteral("DBusResponseWaiter"), DBusResponseWaiter::instance());
}

#include "moc_kdeconnectdeclarativeplugin.cpp"
