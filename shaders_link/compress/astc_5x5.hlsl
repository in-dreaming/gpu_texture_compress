// ASTC 5x5: subsample to 16 pixels at 4x4 grid positions and use the 4x4
// encode path (PCA + QUANT_12 + ISE). The output block has 4x4 weight-grid
// mode bits; the ASTC 5x5 format decoder bilinearly interpolates the 16 grid
// weights to 25 pixels at decode time. This jumps weight precision from
// QUANT_8 (8 levels) to QUANT_12 (12 levels) — same path that gives ASTC_4x4
// its 47.78 dB.

#ifndef COMPRESS_ASTC_5X5_HLSL
#define COMPRESS_ASTC_5X5_HLSL

#define BLOCK_6X6 0
#define HAS_ALPHA 0
#include "astc_encode_core.hlsl"

uint4 compress_astc_5x5(float4 pixels[25])
{
    // 4x4 grid sample positions in a 5x5 block:
    //   px = (gx * 4 + 1) / 3 -> {0, 1, 3, 4}
    //   py same -> {0, 1, 3, 4}
    float4 texels[BLOCK_SIZE];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 4u + 1u) / 3u;
            uint py = ((uint)gy * 4u + 1u) / 3u;
            uint pidx = py * 5u + px;
            texels[gy * 4 + gx] = pixels[pidx] * 255.0f;
        }
    }
    return encode_block(texels);
}

#endif // COMPRESS_ASTC_5X5_HLSL
