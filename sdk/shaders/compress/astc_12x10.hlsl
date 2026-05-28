#ifndef COMPRESS_ASTC_12X10_HLSL
#define COMPRESS_ASTC_12X10_HLSL

#include "astc_common.hlsl"

//=============================================================================
// ASTC 12x10 Block Compression
// Block: 12x10 = 120 pixels
// Grid:  4x4 = 16 weights (proportional mapping)
// Mode:  QUANT_4 (2 bits/weight), CEM 8 (LDR RGB Direct)
//=============================================================================

uint4 compress_astc_12x10(float4 pixels[120])
{
    // NOTE: 12x10 format currently uses void-extent (constant color)
    // because 4x4 weight grids are incompatible with 120-pixel blocks.
    // Proper implementation requires 4x3, 5x3, or 6x3 weight grid with custom
    // block mode encoding. This is a limitation of the simplified encoder.

    float4 avg = float4(0, 0, 0, 1);
    for (int i = 0; i < 120; i++)
    {
        avg += pixels[i];
    }
    avg /= 120.0f;

    return astc_void_extent(avg);
}

#endif // COMPRESS_ASTC_12X10_HLSL
