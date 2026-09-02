kdeconnect_add_plugin(kdeconnect_tailscale SOURCES tailscaleplugin.cpp)
target_link_libraries(kdeconnect_tailscale
    kdeconnectcore
    Qt::DBus
    KF6::I18n
)
