idf_component_register(
    SRCS "wifi_settings_storage.c" "mqtt_settings_storage.c" "wifi_provisioning.c" "wifi_http_server.c" "dns_server.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos mbedtls esp_common esp_timer nvs_flash esp_http_server esp_wifi esp_netif lwip spiffs mqtt
    PRIV_REQUIRES esp_driver_gpio esp_event
)

# Build SPIFFS filesystem image from spiffs_image directory
spiffs_create_partition_image(spiffs ${CMAKE_CURRENT_SOURCE_DIR}/spiffs_image FLASH_IN_PROJECT)
