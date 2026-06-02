// ASTC 5x4: subsample to 16 pixels at 4x4 grid positions and use the 4x4
// encode path (PCA + QUANT_12 + ISE).
//
// 5x5 weight grid is INVALID in 5x4 block (block height 4 < grid height 5),
// so the variable-grid encoder path is not applicable here. Keeping the
// existing 4x4-grid path which gives 37.35 dB on Khronos LDR-RGB.

#ifndef COMPRESS_ASTC_5X4_HLSL
#define COMPRESS_ASTC_5X4_HLSL

#define BLOCK_6X6 0
#define HAS_ALPHA 0
#include "astc_encode_core.hlsl"

uint4 compress_astc_5x4(float4 pixels[20])
{
    // 4x4 grid in 5x4 block:
    //   px = (gx * 4 + 1) / 3 -> {0, 1, 3, 4}
    //   py = (gy * 3 + 1) / 3 -> {0, 1, 2, 3}
    float4 texels[BLOCK_SIZE];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 4u + 1u) / 3u;
            uint py = ((uint)gy * 3u + 1u) / 3u;
            uint pidx = py * 5u + px;
            texels[gy * 4 + gx] = pixels[pidx] * 255.0f;
        }
    }
    return encode_block(texels);
}

#endif // COMPRESS_ASTC_5X4_HLSL
