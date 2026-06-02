// ASTC 8x8: 5x5 weight grid encoder via the generic parameterized template.
// PCA on all 64 texels, 5x5 grid sampled by bilinear, Q5 weights, Q256 endpoints.

#ifndef COMPRESS_ASTC_8X8_HLSL
#define COMPRESS_ASTC_8X8_HLSL

#define BLOCK_W 8
#define BLOCK_H 8
#define BLOCK_SIZE 64
#define GRID_FUNC_NAME encode_block_5x5_in_8x8
#include "astc_encode_grid5x5_generic.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_8x8(float4 pixels[64])
{
    float4 texels[64];
    [unroll] for (int i = 0; i < 64; i++) {
        texels[i] = pixels[i] * 255.0f;
    }
    return encode_block_5x5_in_8x8(texels);
}

#endif // COMPRESS_ASTC_8X8_HLSL
