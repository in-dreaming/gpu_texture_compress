// ASTC 8x5: dual-mode encoder (5x5+Q5 vs 4x4+Q12 per block).
#ifndef COMPRESS_ASTC_8X5_HLSL
#define COMPRESS_ASTC_8X5_HLSL

#define BLOCK_W 8
#define BLOCK_H 5
#define BLOCK_SIZE 40
#define GRID_FUNC_NAME encode_block_dual_in_8x5
#include "astc_encode_dual.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_8x5(float4 pixels[40])
{
    float4 texels[40];
    [unroll] for (int i = 0; i < 40; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_dual_in_8x5(texels);
}

#endif
