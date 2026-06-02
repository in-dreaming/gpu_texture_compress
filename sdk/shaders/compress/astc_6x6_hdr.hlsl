#ifndef ASTC_6x6_HDR_HLSL
#define ASTC_6x6_HDR_HLSL

//=============================================================================
// ASTC 6x6 HDR Compression
// Compresses 6x6 blocks of HDR RGBA pixels
//=============================================================================

#include "astc_common.hlsl"
#include "astc_encode_core.hlsl"
#include "astc_hdr.hlsl"

// 6x6 block with 16 pixels sampled to 4x4 weight grid
uint4 compress_astc_6x6_hdr(float4 pixels[36])
{
    // Compute HDR scale factor
    float max_hdr_val = 0.0;
    [unroll] for (int i = 0; i < 36; i++) {
        max_hdr_val = max(max_hdr_val, max(pixels[i].r, max(pixels[i].g, pixels[i].b)));
    }
    max_hdr_val = max(max_hdr_val, 1.0);
    
    // Sample 16 points from 36 using bilinear grid mapping
    // Map 4x4 grid to 6x6 block positions
    float4 texels[16];
    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            // Map grid (0-3) to pixel (0-5)
            uint px = ((uint)gx * 5 + 1) / 3;
            uint py = ((uint)gy * 5 + 1) / 3;
            float3 hdr_rgb = pixels[py * 6 + px].rgb;
            // Normalize to 0-255 range for encoding
            texels[gy * 4 + gx] = float4(hdr_rgb / max_hdr_val * 255.0, pixels[py * 6 + px].a * 255.0);
        }
    }
    
    // Use existing 4x4 encode core on normalized values
    return encode_block(texels);
}

#endif // ASTC_6x6_HDR_HLSL
