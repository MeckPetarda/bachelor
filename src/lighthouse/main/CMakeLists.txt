idf_component_register(
    SRCS "lighthouse.c" "io_controller.c" "rfid_reader.c" "wifi_manager.c" "my_mqtt_client.c" "offline_event_logger.c" "battery_monitor.c" "time_sync.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos esp_driver_uart esp_wifi esp_netif nvs_flash mqtt joltwallet__littlefs wifi_provisioning lwip
    PRIV_REQUIRES esp_driver_gpio esp_event esp_adc
)
