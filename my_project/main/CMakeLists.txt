idf_component_register(
    SRCS "my_project.c" "uart_reader.c" "wifi_manager.c" "my_mqtt_client.c" "offline_event_logger.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos esp_driver_uart esp_wifi esp_netif nvs_flash mqtt esp_littlefs
    PRIV_REQUIRES esp_driver_gpio esp_event
)
