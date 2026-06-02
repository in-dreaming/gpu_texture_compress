// ASTC 12x12: dual-mode encoder (5x5+Q5 vs 4x4+Q12 per block).
#ifndef COMPRESS_ASTC_12X12_HLSL
#define COMPRESS_ASTC_12X12_HLSL

#define BLOCK_W 12
#define BLOCK_H 12
#define BLOCK_SIZE 144
#define GRID_FUNC_NAME encode_block_dual_in_12x12
#include "astc_encode_dual.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_12x12(float4 pixels[144])
{
    float4 texels[144];
    [unroll] for (int i = 0; i < 144; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_dual_in_12x12(texels);
}

#endif
