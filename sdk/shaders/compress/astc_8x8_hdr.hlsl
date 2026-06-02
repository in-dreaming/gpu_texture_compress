#ifndef ASTC_8x8_HDR_HLSL
#define ASTC_8x8_HDR_HLSL

//=============================================================================
// ASTC 8x8 HDR Compression
// Compresses 8x8 blocks of HDR RGBA pixels
//=============================================================================

#include "astc_common.hlsl"
#include "astc_encode_core.hlsl"
#include "astc_hdr.hlsl"

// 8x8 block with 64 pixels sampled to 4x4 weight grid
uint4 compress_astc_8x8_hdr(float4 pixels[64])
{
    // Compute HDR scale factor
    float max_hdr_val = 0.0;
    [unroll] for (int i = 0; i < 64; i++) {
        max_hdr_val = max(max_hdr_val, max(pixels[i].r, max(pixels[i].g, pixels[i].b)));
    }
    max_hdr_val = max(max_hdr_val, 1.0);
    
    // Sample 16 points from 64 using bilinear grid mapping
    float4 texels[16];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            // Map grid (0-3) to pixel (0-7)
            uint px = ((uint)gx * 7 + 1) / 3;
            uint py = ((uint)gy * 7 + 1) / 3;
            float3 hdr_rgb = pixels[py * 8 + px].rgb;
            texels[gy * 4 + gx] = float4(hdr_rgb / max_hdr_val * 255.0, pixels[py * 8 + px].a * 255.0);
        }
    }
    
    return encode_block(texels);
}

#endif // ASTC_8x8_HDR_HLSL
