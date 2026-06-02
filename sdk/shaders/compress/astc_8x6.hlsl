// ASTC 8x6: 5x5 weight grid encoder.
#ifndef COMPRESS_ASTC_8X6_HLSL
#define COMPRESS_ASTC_8X6_HLSL

#define BLOCK_W 8
#define BLOCK_H 6
#define BLOCK_SIZE 48
#define GRID_FUNC_NAME encode_block_5x5_in_8x6
#include "astc_encode_grid5x5_generic.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_8x6(float4 pixels[48])
{
    float4 texels[48];
    [unroll] for (int i = 0; i < 48; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_5x5_in_8x6(texels);
}

#endif
