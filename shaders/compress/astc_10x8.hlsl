// ASTC 10x8: 5x5 weight grid encoder.
#ifndef COMPRESS_ASTC_10X8_HLSL
#define COMPRESS_ASTC_10X8_HLSL

#define BLOCK_W 10
#define BLOCK_H 8
#define BLOCK_SIZE 80
#define GRID_FUNC_NAME encode_block_5x5_in_10x8
#include "astc_encode_grid5x5_generic.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_10x8(float4 pixels[80])
{
    float4 texels[80];
    [unroll] for (int i = 0; i < 80; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_5x5_in_10x8(texels);
}

#endif
