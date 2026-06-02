#pragma once

// gtc_formats.h - SDK format definitions
// This header describes all supported compression formats and their properties.
// Independent of any specific graphics API.

#ifdef __cplusplus
#include <cstdint>
namespace gtc {
#endif

// Supported texture compression formats
enum GtcFormat {
    // BCn formats (4x4 blocks)
    GTC_FORMAT_BC1 = 0,      // RGB,  4 bpp, 4x4 block, 64-bit output
    GTC_FORMAT_BC3,          // RGBA, 8 bpp, 4x4 block, 128-bit output
    GTC_FORMAT_BC4,          // R,    4 bpp, 4x4 block, 64-bit output
    GTC_FORMAT_BC5,          // RG,   8 bpp, 4x4 block, 128-bit output
    GTC_FORMAT_BC6H,         // RGB HDR, 8 bpp, 4x4 block, 128-bit output
    GTC_FORMAT_BC7,          // RGBA, 8 bpp, 4x4 block, 128-bit output

    // ASTC formats (all 14 block sizes, 128-bit output each)
    GTC_FORMAT_ASTC_4x4,    // 8.00 bpp
    GTC_FORMAT_ASTC_5x4,    // 6.40 bpp
    GTC_FORMAT_ASTC_5x5,    // 5.12 bpp
    GTC_FORMAT_ASTC_6x5,    // 4.27 bpp
    GTC_FORMAT_ASTC_6x6,    // 3.56 bpp
    GTC_FORMAT_ASTC_8x5,    // 3.20 bpp
    GTC_FORMAT_ASTC_8x6,    // 2.67 bpp
    GTC_FORMAT_ASTC_8x8,    // 2.00 bpp
    GTC_FORMAT_ASTC_10x5,   // 2.56 bpp
    GTC_FORMAT_ASTC_10x6,   // 2.13 bpp
    GTC_FORMAT_ASTC_10x8,   // 1.60 bpp
    GTC_FORMAT_ASTC_10x10,  // 1.28 bpp
    GTC_FORMAT_ASTC_12x10,  // 1.07 bpp
    GTC_FORMAT_ASTC_12x12,  // 0.89 bpp

    // HDR ASTC formats (HDR RGB + LDR Alpha profile)
    GTC_FORMAT_ASTC_4x4_HDR,    // 8.00 bpp, HDR RGB
    GTC_FORMAT_ASTC_5x4_HDR,    // 6.40 bpp, HDR RGB
    GTC_FORMAT_ASTC_5x5_HDR,    // 5.12 bpp, HDR RGB
    GTC_FORMAT_ASTC_6x5_HDR,    // 4.27 bpp, HDR RGB
    GTC_FORMAT_ASTC_6x6_HDR,    // 3.56 bpp, HDR RGB
    GTC_FORMAT_ASTC_8x5_HDR,    // 3.20 bpp, HDR RGB
    GTC_FORMAT_ASTC_8x6_HDR,    // 2.67 bpp, HDR RGB
    GTC_FORMAT_ASTC_8x8_HDR,    // 2.00 bpp, HDR RGB
    GTC_FORMAT_ASTC_10x5_HDR,   // 2.56 bpp, HDR RGB
    GTC_FORMAT_ASTC_10x6_HDR,   // 2.13 bpp, HDR RGB
    GTC_FORMAT_ASTC_10x8_HDR,   // 1.60 bpp, HDR RGB
    GTC_FORMAT_ASTC_10x10_HDR,  // 1.28 bpp, HDR RGB
    GTC_FORMAT_ASTC_12x10_HDR,  // 1.07 bpp, HDR RGB
    GTC_FORMAT_ASTC_12x12_HDR,  // 0.89 bpp, HDR RGB

    GTC_FORMAT_COUNT
};

// Block dimensions for each format
struct GtcFormatInfo {
    uint32_t block_width;
    uint32_t block_height;
    uint32_t block_bytes;    // Compressed block size in bytes (8 for BC1/BC4, 16 for all others)
    float    bits_per_pixel; // Effective bits per pixel
    const char* name;
    const char* shader_file; // Relative path to dispatch shader (from sdk/shaders/)
};

#ifdef __cplusplus

inline const GtcFormatInfo& get_format_info(GtcFormat format) {
    static const GtcFormatInfo infos[GTC_FORMAT_COUNT] = {
        // BCn
        {  4,  4,  8, 4.00f, "BC1",        "dispatch/bc1_cs.hlsl"       },
        {  4,  4, 16, 8.00f, "BC3",        "dispatch/bc3_cs.hlsl"       },
        {  4,  4,  8, 4.00f, "BC4",        "dispatch/bc4_cs.hlsl"       },
        {  4,  4, 16, 8.00f, "BC5",        "dispatch/bc5_cs.hlsl"       },
        {  4,  4, 16, 8.00f, "BC6H",       "dispatch/bc6h_cs.hlsl"      },
        {  4,  4, 16, 8.00f, "BC7",        "dispatch/bc7_cs.hlsl"       },
        // ASTC
        {  4,  4, 16, 8.00f, "ASTC_4x4",   "dispatch/astc_4x4_cs.hlsl"  },
        {  5,  4, 16, 6.40f, "ASTC_5x4",   "dispatch/astc_5x4_cs.hlsl"  },
        {  5,  5, 16, 5.12f, "ASTC_5x5",   "dispatch/astc_5x5_cs.hlsl"  },
        {  6,  5, 16, 4.27f, "ASTC_6x5",   "dispatch/astc_6x5_cs.hlsl"  },
        {  6,  6, 16, 3.56f, "ASTC_6x6",   "dispatch/astc_6x6_cs.hlsl"  },
        {  8,  5, 16, 3.20f, "ASTC_8x5",   "dispatch/astc_8x5_cs.hlsl"  },
        {  8,  6, 16, 2.67f, "ASTC_8x6",   "dispatch/astc_8x6_cs.hlsl"  },
        {  8,  8, 16, 2.00f, "ASTC_8x8",   "dispatch/astc_8x8_cs.hlsl"  },
        { 10,  5, 16, 2.56f, "ASTC_10x5",  "dispatch/astc_10x5_cs.hlsl" },
        { 10,  6, 16, 2.13f, "ASTC_10x6",  "dispatch/astc_10x6_cs.hlsl" },
        { 10,  8, 16, 1.60f, "ASTC_10x8",  "dispatch/astc_10x8_cs.hlsl" },
        { 10, 10, 16, 1.28f, "ASTC_10x10", "dispatch/astc_10x10_cs.hlsl"},
        { 12, 10, 16, 1.07f, "ASTC_12x10", "dispatch/astc_12x10_cs.hlsl"},
        { 12, 12, 16, 0.89f, "ASTC_12x12", "dispatch/astc_12x12_cs.hlsl"},
        // HDR ASTC
        {  4,  4, 16, 8.00f, "ASTC_4x4_HDR",  "dispatch/astc_4x4_hdr_cs.hlsl"},
        {  5,  4, 16, 6.40f, "ASTC_5x4_HDR",  "dispatch/astc_5x4_hdr_cs.hlsl"},
        {  5,  5, 16, 5.12f, "ASTC_5x5_HDR",  "dispatch/astc_5x5_hdr_cs.hlsl"},
        {  6,  5, 16, 4.27f, "ASTC_6x5_HDR",  "dispatch/astc_6x5_hdr_cs.hlsl"},
        {  6,  6, 16, 3.56f, "ASTC_6x6_HDR",  "dispatch/astc_6x6_hdr_cs.hlsl"},
        {  8,  5, 16, 3.20f, "ASTC_8x5_HDR",  "dispatch/astc_8x5_hdr_cs.hlsl"},
        {  8,  6, 16, 2.67f, "ASTC_8x6_HDR",  "dispatch/astc_8x6_hdr_cs.hlsl"},
        {  8,  8, 16, 2.00f, "ASTC_8x8_HDR",  "dispatch/astc_8x8_hdr_cs.hlsl"},
        { 10,  5, 16, 2.56f, "ASTC_10x5_HDR", "dispatch/astc_10x5_hdr_cs.hlsl"},
        { 10,  6, 16, 2.13f, "ASTC_10x6_HDR", "dispatch/astc_10x6_hdr_cs.hlsl"},
        { 10,  8, 16, 1.60f, "ASTC_10x8_HDR", "dispatch/astc_10x8_hdr_cs.hlsl"},
        { 10, 10, 16, 1.28f, "ASTC_10x10_HDR", "dispatch/astc_10x10_hdr_cs.hlsl"},
        { 12, 10, 16, 1.07f, "ASTC_12x10_HDR", "dispatch/astc_12x10_hdr_cs.hlsl"},
        { 12, 12, 16, 0.89f, "ASTC_12x12_HDR", "dispatch/astc_12x12_hdr_cs.hlsl"},
    };
    return infos[format];
}

} // namespace gtc
#endif
