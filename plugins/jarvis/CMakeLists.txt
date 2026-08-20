kdeconnect_add_plugin(kdeconnect_jarvis SOURCES jarvisplugin.cpp)
target_link_libraries(kdeconnect_jarvis
    kdeconnectcore
    Qt::DBus
    KF6::I18n)

install(FILES "kdeconnect_jarvis_config.qml" DESTINATION ${KDE_INSTALL_DATADIR}/kdeconnect)
