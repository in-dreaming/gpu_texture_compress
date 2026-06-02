// ASTC 5x4: 1:1 grid (5x4) + Q8 weights, encoder sees all 20 pixels.
// Block mode 211. Bit budget: 17 + 48 + 60 = 125.
#ifndef COMPRESS_ASTC_5X4_HLSL
#define COMPRESS_ASTC_5X4_HLSL

#define BLOCK_W 5
#define BLOCK_H 4
#define BLOCK_SIZE 20
#define WEIGHT_Q_INDEX 5      // QUANT_8
#define WEIGHT_RANGE_M1 7     // 8 levels - 1
#define WEIGHT_BITS 3
#define ONETOONE_FUNC_NAME encode_block_5x4_q8
#define ONETOONE_BLOCKMODE 211
#include "astc_encode_grid_1to1.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef WEIGHT_Q_INDEX
#undef WEIGHT_RANGE_M1
#undef WEIGHT_BITS
#undef ONETOONE_FUNC_NAME
#undef ONETOONE_BLOCKMODE

uint4 compress_astc_5x4(float4 pixels[20])
{
    float4 texels[20];
    [unroll] for (int i = 0; i < 20; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_5x4_q8(texels);
}

#endif
