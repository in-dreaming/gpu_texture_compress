// ASTC 8x5: 5x5 weight grid encoder.
#ifndef COMPRESS_ASTC_8X5_HLSL
#define COMPRESS_ASTC_8X5_HLSL

#define BLOCK_W 8
#define BLOCK_H 5
#define BLOCK_SIZE 40
#define GRID_FUNC_NAME encode_block_5x5_in_8x5
#include "astc_encode_grid5x5_generic.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_8x5(float4 pixels[40])
{
    float4 texels[40];
    [unroll] for (int i = 0; i < 40; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_5x5_in_8x5(texels);
}

#endif
