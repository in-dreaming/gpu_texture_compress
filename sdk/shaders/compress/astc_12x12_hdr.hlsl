#ifndef ASTC_12x12_HDR_HLSL
#define ASTC_12x12_HDR_HLSL

//=============================================================================
// ASTC 12x12 HDR Compression
// 144 pixels -> 4x4 weight grid
//=============================================================================

#include "astc_common.hlsl"
#include "astc_encode_core.hlsl"
#include "astc_hdr.hlsl"

uint4 compress_astc_12x12_hdr(float4 pixels[144])
{
    float max_hdr_val = 0.0;
    [unroll] for (int i = 0; i < 144; i++) {
        max_hdr_val = max(max_hdr_val, max(pixels[i].r, max(pixels[i].g, pixels[i].b)));
    }
    max_hdr_val = max(max_hdr_val, 1.0);
    
    float4 texels[16];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            uint px = ((uint)gx * 11 + 1) / 3;
            uint py = ((uint)gy * 11 + 1) / 3;
            float3 hdr_rgb = pixels[py * 12 + px].rgb;
            texels[gy * 4 + gx] = float4(hdr_rgb / max_hdr_val * 255.0, pixels[py * 12 + px].a * 255.0);
        }
    }
    
    return encode_block(texels);
}

#endif // ASTC_12x12_HDR_HLSL
