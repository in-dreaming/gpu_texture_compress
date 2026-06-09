set(GTC_SOURCES
    main.cpp
    gpu_device.cpp
    texture_loader.cpp
    shader_compiler.cpp
    compute_dispatch.cpp
    compression_pipeline.cpp
    decompressor.cpp
    eval_metrics.cpp
    experiment_runner.cpp
    comparison_baker.cpp
    results_logger.cpp
)

add_executable(gtc_runner ${GTC_SOURCES})

target_include_directories(gtc_runner PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/external/stb
    ${CMAKE_SOURCE_DIR}/deps/astc-encoder/Source
    ${CMAKE_SOURCE_DIR}/deps/DirectXTex/DirectXTex
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(gtc_runner PRIVATE
    SDL3::SDL3-static
    astcdec-avx2-static
    DirectXTex
)

# Copy SDK shader directory to build output for runtime access
add_custom_command(TARGET gtc_runner POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${CMAKE_SOURCE_DIR}/sdk/shaders
    $<TARGET_FILE_DIR:gtc_runner>/shaders
)

# Copy infrastructure shader directory
add_custom_command(TARGET gtc_runner POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${CMAKE_SOURCE_DIR}/shaders/infrastructure
    $<TARGET_FILE_DIR:gtc_runner>/shaders/infrastructure
)
