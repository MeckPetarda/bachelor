idf_component_register(
    SRCS "my_project.c" "uart_reader.c" "wifi_manager.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos esp_driver_uart esp_wifi esp_netif nvs_flash
    PRIV_REQUIRES esp_driver_gpio esp_event
)
