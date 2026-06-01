// ASTC 8x5: Q12 path via 4x4 subsample.
#ifndef COMPRESS_ASTC_8X5_HLSL
#define COMPRESS_ASTC_8X5_HLSL

#define BLOCK_6X6 0
#define HAS_ALPHA 0
#include "astc_encode_core.hlsl"

uint4 compress_astc_8x5(float4 pixels[40])
{
    // 4x4 grid in 8x5 block:
    //   px = (gx * 7 + 1) / 3 -> {0, 2, 5, 7}
    //   py = (gy * 4 + 1) / 3 -> {0, 1, 3, 4}
    float4 texels[BLOCK_SIZE];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 7u + 1u) / 3u;
            uint py = ((uint)gy * 4u + 1u) / 3u;
            uint pidx = py * 8u + px;
            texels[gy * 4 + gx] = pixels[pidx] * 255.0f;
        }
    }
    return encode_block(texels);
}

#endif
