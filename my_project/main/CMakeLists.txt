idf_component_register(
    SRCS "my_project.c" "uart_reader.c"
    INCLUDE_DIRS "."
    REQUIRES driver freertos esp_driver_uart
    PRIV_REQUIRES esp_driver_gpio
)
