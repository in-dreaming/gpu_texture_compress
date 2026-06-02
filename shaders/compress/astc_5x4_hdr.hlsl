#ifndef ASTC_5x4_HDR_HLSL
#define ASTC_5x4_HDR_HLSL

#include "astc_hdr_proper.hlsl"

uint4 compress_astc_5x4_hdr(float4 pixels[20])
{
    float4 texels[16];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 4u + 1u) / 3u;
            uint py = (uint)gy;  // 4 rows direct
            texels[gy * 4 + gx] = pixels[py * 5u + px];
        }
    }
    return astc_compress_4x4_hdr_proper(texels);
}

#endif // ASTC_5x4_HDR_HLSL
