#ifndef ASTC_12x12_HDR_HLSL
#define ASTC_12x12_HDR_HLSL

#include "astc_hdr_proper.hlsl"

uint4 compress_astc_12x12_hdr(float4 pixels[144])
{
    float4 texels[16];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 11u + 1u) / 3u;
            uint py = ((uint)gy * 11u + 1u) / 3u;
            texels[gy * 4 + gx] = pixels[py * 12u + px];
        }
    }
    return astc_compress_4x4_hdr_proper(texels);
}

#endif // ASTC_12x12_HDR_HLSL
