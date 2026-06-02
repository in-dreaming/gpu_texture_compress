#ifndef ASTC_10x6_HDR_HLSL
#define ASTC_10x6_HDR_HLSL

//=============================================================================
// ASTC 10x6 HDR Compression
// 60 pixels -> 4x4 weight grid
//=============================================================================

#include "astc_common.hlsl"
#include "astc_encode_core.hlsl"
#include "astc_hdr.hlsl"

uint4 compress_astc_10x6_hdr(float4 pixels[60])
{
    float max_hdr_val = 0.0;
    [unroll] for (int i = 0; i < 60; i++) {
        max_hdr_val = max(max_hdr_val, max(pixels[i].r, max(pixels[i].g, pixels[i].b)));
    }
    max_hdr_val = max(max_hdr_val, 1.0);
    
    float4 texels[16];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 9 + 1) / 3;
            uint py = ((uint)gy * 5 + 1) / 3;
            float3 hdr_rgb = pixels[py * 10 + px].rgb;
            texels[gy * 4 + gx] = float4(hdr_rgb / max_hdr_val * 255.0, pixels[py * 10 + px].a * 255.0);
        }
    }
    
    return encode_block(texels);
}

#endif // ASTC_10x6_HDR_HLSL
