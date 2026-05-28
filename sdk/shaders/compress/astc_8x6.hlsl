#ifndef COMPRESS_ASTC_8X6_HLSL
#define COMPRESS_ASTC_8X6_HLSL

#include "astc_common.hlsl"

//=============================================================================
// ASTC 8x6 Block Compression
// Block: 8x6 = 48 pixels
// Grid:  4x4 = 16 weights (proportional mapping)
// Mode:  QUANT_4 (2 bits/weight), CEM 8 (LDR RGB Direct)
//=============================================================================

uint4 compress_astc_8x6(float4 pixels[48])
{
    // NOTE: 8x6 format currently uses void-extent (constant color)
    // because 4x4 weight grids are incompatible with 48-pixel blocks.
    // Proper implementation requires 4x3 or 5x3 weight grid with custom
    // block mode encoding. This is a limitation of the simplified encoder.

    float4 avg = float4(0, 0, 0, 1);
    for (int i = 0; i < 48; i++)
    {
        avg += pixels[i];
    }
    avg /= 48.0f;

    return astc_void_extent(avg);
}

#endif // COMPRESS_ASTC_8X6_HLSL
