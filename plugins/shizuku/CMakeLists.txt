kdeconnect_add_plugin(kdeconnect_shizuku SOURCES shizukuplugin.cpp)
target_link_libraries(kdeconnect_shizuku
    kdeconnectcore
    Qt::DBus
    KF6::I18n
)
