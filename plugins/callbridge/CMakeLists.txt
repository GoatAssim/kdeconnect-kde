kdeconnect_add_plugin(kdeconnect_callbridge SOURCES callbridgeplugin.cpp)
target_link_libraries(kdeconnect_callbridge
    kdeconnectcore
    Qt::DBus
    KF6::I18n
    KF6::Notifications
)