#pragma once

// shared_types.h - Shared between C++ host code and HLSL shaders
// Keep in sync with cbuffer declarations in shader files

#ifdef __cplusplus
#include <cstdint>
namespace gtc {
#endif

struct CompressParams {
    int32_t TexWidth;       // Source texture width in pixels
    int32_t TexHeight;      // Source texture height in pixels
    int32_t BlocksX;        // Number of blocks horizontally = ceil(width / block_dim_x)
    int32_t BlocksY;        // Number of blocks vertically = ceil(height / block_dim_y)
    int32_t QualityLevel;   // 0=fastest, 1=balanced, 2=best
    int32_t Flags;          // Bitfield: see GTC_FLAG_* below
    float   Pad0;           // Padding for 16-byte alignment
    float   Pad1;
};

// Flag bits for CompressParams.Flags
#define GTC_FLAG_NORMALMAP  (1 << 0)
#define GTC_FLAG_HAS_ALPHA  (1 << 1)
#define GTC_FLAG_SRGB       (1 << 2)

#ifdef __cplusplus
static_assert(sizeof(CompressParams) == 32, "CompressParams must be 32 bytes for GPU alignment");
} // namespace gtc
#endif
