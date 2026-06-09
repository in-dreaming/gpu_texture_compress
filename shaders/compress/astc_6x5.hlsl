// ASTC 6x5: triple-mode block-mode search.
//   Mode A: 5x5 grid + Q5         (block mode 242)
//   Mode B: 4x4 grid + Q12        (block mode 593)
//   Mode C: 6x5 grid + Q4 (1:1)   (block mode 354)
#ifndef COMPRESS_ASTC_6X5_HLSL
#define COMPRESS_ASTC_6X5_HLSL

#define BLOCK_W 6
#define BLOCK_H 5
#define BLOCK_SIZE 30
#define GRID_FUNC_NAME encode_block_triple_in_6x5
#define T1_WEIGHT_Q_INDEX 2      // QUANT_4
#define T1_WEIGHT_RANGE_M1 3
#define T1_WEIGHT_BITS 2
#define T1_BLOCKMODE 354

// QualityLevel-based compilation (0=fast, 1=balanced, 2=best)
#ifndef QUALITY_LEVEL
#define QUALITY_LEVEL 1  // Default: Mode A+B (balanced)
#endif

#include "astc_encode_triple.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME
#undef T1_WEIGHT_Q_INDEX
#undef T1_WEIGHT_RANGE_M1
#undef T1_WEIGHT_BITS
#undef T1_BLOCKMODE

uint4 compress_astc_6x5(float4 pixels[30])
{
    float4 texels[30];
    [unroll] for (int i = 0; i < 30; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_triple_in_6x5(texels);
}

#endif
