idf_component_register(
    SRCS "step_counter.cpp"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES nvs_flash esp_driver_i2c esp_timer
)
