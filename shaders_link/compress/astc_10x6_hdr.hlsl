#ifndef ASTC_10x6_HDR_HLSL
#define ASTC_10x6_HDR_HLSL

#include "astc_hdr_proper.hlsl"

uint4 compress_astc_10x6_hdr(float4 pixels[60])
{
    float4 texels[16];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 9u + 1u) / 3u;
            uint py = ((uint)gy * 5u + 1u) / 3u;
            texels[gy * 4 + gx] = pixels[py * 10u + px];
        }
    }
    return astc_compress_4x4_hdr_proper(texels);
}

#endif // ASTC_10x6_HDR_HLSL
