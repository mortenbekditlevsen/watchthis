idf_component_register(
    SRCS "music_player.cpp"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES file_store nvs_flash esp_timer
)
