idf_component_register(
    SRCS "wifi_settings_storage.c" "wifi_provisioning.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos mbedtls esp_common esp_timer nvs_flash
    PRIV_REQUIRES esp_driver_gpio esp_event
)
