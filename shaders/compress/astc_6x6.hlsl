// ASTC 6x6: subsample to 16 pixels at 4x4 grid positions and use the 4x4
// encode path (PCA + QUANT_12 + ISE). Decoder bilinearly maps to 36 pixels.

#ifndef COMPRESS_ASTC_6X6_HLSL
#define COMPRESS_ASTC_6X6_HLSL

#define BLOCK_6X6 0
#define HAS_ALPHA 0
#include "astc_encode_core.hlsl"

uint4 compress_astc_6x6(float4 pixels[36])
{
    // 4x4 grid in 6x6 block:
    //   px = (gx * 5 + 1) / 3 -> {0, 2, 3, 5}
    //   py = (gy * 5 + 1) / 3 -> {0, 2, 3, 5}
    float4 texels[BLOCK_SIZE];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 5u + 1u) / 3u;
            uint py = ((uint)gy * 5u + 1u) / 3u;
            uint pidx = py * 6u + px;
            texels[gy * 4 + gx] = pixels[pidx] * 255.0f;
        }
    }
    return encode_block(texels);
}

#endif // COMPRESS_ASTC_6X6_HLSL
