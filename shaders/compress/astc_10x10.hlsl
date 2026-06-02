// ASTC 10x10: dual-mode encoder (5x5+Q5 vs 4x4+Q12 per block).
#ifndef COMPRESS_ASTC_10X10_HLSL
#define COMPRESS_ASTC_10X10_HLSL

#define BLOCK_W 10
#define BLOCK_H 10
#define BLOCK_SIZE 100
#define GRID_FUNC_NAME encode_block_dual_in_10x10
#include "astc_encode_dual.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_10x10(float4 pixels[100])
{
    float4 texels[100];
    [unroll] for (int i = 0; i < 100; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_dual_in_10x10(texels);
}

#endif
