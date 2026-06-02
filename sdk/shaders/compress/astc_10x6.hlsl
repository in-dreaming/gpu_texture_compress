// ASTC 10x6: dual-mode encoder (5x5+Q5 vs 4x4+Q12 per block).
#ifndef COMPRESS_ASTC_10X6_HLSL
#define COMPRESS_ASTC_10X6_HLSL

#define BLOCK_W 10
#define BLOCK_H 6
#define BLOCK_SIZE 60
#define GRID_FUNC_NAME encode_block_dual_in_10x6
#include "astc_encode_dual.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_10x6(float4 pixels[60])
{
    float4 texels[60];
    [unroll] for (int i = 0; i < 60; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_dual_in_10x6(texels);
}

#endif
