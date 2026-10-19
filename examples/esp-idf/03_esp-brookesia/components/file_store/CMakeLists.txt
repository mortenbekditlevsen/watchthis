idf_component_register(
    SRCS "file_store.cpp"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES joltwallet__littlefs
)

# Content preloaded into the `store` partition: components copy files into this directory at configure time (e.g.
# brookesia_app_cats adds photos/) and LittleFS builds the partition image from it. It is NOT part of `idf.py flash`
# (that would wipe uploaded files every time); write it explicitly with `idf.py store-flash` (first time, or to reset).
set(FILE_STORE_PRELOAD_DIR "${CMAKE_BINARY_DIR}/store_preload" CACHE INTERNAL "")
file(MAKE_DIRECTORY "${FILE_STORE_PRELOAD_DIR}/photos" "${FILE_STORE_PRELOAD_DIR}/music")
partition_table_get_partition_info(store_size "--partition-name store" "size")
if(store_size)
    littlefs_create_partition_image(store "${FILE_STORE_PRELOAD_DIR}")
else()
    message(WARNING "No 'store' partition in the partition table")
endif()
