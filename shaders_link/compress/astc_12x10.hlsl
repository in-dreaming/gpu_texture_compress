// ASTC 12x10: 5x5 weight grid encoder.
#ifndef COMPRESS_ASTC_12X10_HLSL
#define COMPRESS_ASTC_12X10_HLSL

#define BLOCK_W 12
#define BLOCK_H 10
#define BLOCK_SIZE 120
#define GRID_FUNC_NAME encode_block_5x5_in_12x10
#include "astc_encode_grid5x5_generic.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_12x10(float4 pixels[120])
{
    float4 texels[120];
    [unroll] for (int i = 0; i < 120; i++) texels[i] = pixels[i] * 255.0f;
    return encode_block_5x5_in_12x10(texels);
}

#endif
