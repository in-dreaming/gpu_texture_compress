// ASTC 6x6: dual-mode encoder. Per-block selection between 5x5+Q5 and 4x4+Q12.
#ifndef COMPRESS_ASTC_6X6_HLSL
#define COMPRESS_ASTC_6X6_HLSL

#define BLOCK_W 6
#define BLOCK_H 6
#define BLOCK_SIZE 36
#define GRID_FUNC_NAME encode_block_dual_in_6x6
#include "astc_encode_dual.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_6x6(float4 pixels[36])
{
    float4 texels[36];
    [unroll] for (int i = 0; i < 36; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_dual_in_6x6(texels);
}

#endif
