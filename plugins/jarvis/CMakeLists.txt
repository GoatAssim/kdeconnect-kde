find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Network WebSockets)

kdeconnect_add_plugin(kdeconnect_jarvis SOURCES jarvisplugin.cpp)
target_link_libraries(kdeconnect_jarvis
    kdeconnectcore
    Qt::DBus
    Qt::Network
    Qt::WebSockets
    KF6::I18n)

install(FILES "kdeconnect_jarvis_config.qml" DESTINATION ${KDE_INSTALL_DATADIR}/kdeconnect)
