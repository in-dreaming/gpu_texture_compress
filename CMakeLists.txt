cmake_minimum_required(VERSION 3.24)
project(gpu_texture_compress VERSION 0.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ─── Options ───────────────────────────────────────────────────────────────────
option(GTC_BUILD_TESTS "Build unit tests" ON)

# ─── SDL3 ──────────────────────────────────────────────────────────────────────
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory(external/SDL)

# ─── ASTC-Encoder (decompression only) ────────────────────────────────────────
set(ASTCENC_DECOMPRESSOR ON CACHE BOOL "" FORCE)
set(ASTCENC_ISA_AVX2 ON CACHE BOOL "" FORCE)
set(ASTCENC_ISA_SSE41 OFF CACHE BOOL "" FORCE)
set(ASTCENC_ISA_SSE2 OFF CACHE BOOL "" FORCE)
set(ASTCENC_ISA_NONE OFF CACHE BOOL "" FORCE)
set(ASTCENC_CLI OFF CACHE BOOL "" FORCE)
set(ASTCENC_UNITTEST OFF CACHE BOOL "" FORCE)
add_subdirectory(deps/astc-encoder)

# ─── DirectXTex (BC decompression) ────────────────────────────────────────────
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(BUILD_SAMPLE OFF CACHE BOOL "" FORCE)
set(BUILD_DX11 OFF CACHE BOOL "" FORCE)
set(BUILD_DX12 OFF CACHE BOOL "" FORCE)
add_subdirectory(deps/DirectXTex)

# ─── stb (header-only) ─────────────────────────────────────────────────────────
add_library(stb_image INTERFACE)
target_include_directories(stb_image INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/external/stb)

# ─── Core executable ───────────────────────────────────────────────────────────
add_subdirectory(src)

# ─── Tests ─────────────────────────────────────────────────────────────────────
if(GTC_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
