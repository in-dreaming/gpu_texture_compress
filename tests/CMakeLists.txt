enable_testing()

add_executable(test_metrics test_metrics.cpp)
target_include_directories(test_metrics PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/external/stb
)
target_link_libraries(test_metrics PRIVATE SDL3::SDL3-static)

add_test(NAME test_metrics COMMAND test_metrics)
