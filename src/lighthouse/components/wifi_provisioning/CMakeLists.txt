idf_component_register(
    SRCS "wifi_settings_storage.c" "wifi_provisioning.c" "wifi_http_server.c" "dns_server.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos mbedtls esp_common esp_timer nvs_flash esp_http_server esp_wifi esp_netif lwip
    PRIV_REQUIRES esp_driver_gpio esp_event
)
