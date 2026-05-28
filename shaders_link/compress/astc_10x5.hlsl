#ifndef COMPRESS_ASTC_10X5_HLSL
#define COMPRESS_ASTC_10X5_HLSL

#include "astc_common.hlsl"

//=============================================================================
// ASTC 10x5 Block Compression
// Block: 10x5 = 50 pixels
// Grid:  4x4 = 16 weights (proportional mapping)
// Mode:  QUANT_4 (2 bits/weight), CEM 8 (LDR RGB Direct)
//=============================================================================

uint4 compress_astc_10x5(float4 pixels[50])
{
    // 1. Find min/max RGB across all pixels
    float3 min_rgb = pixels[0].rgb;
    float3 max_rgb = pixels[0].rgb;
    for (int i = 1; i < 50; i++)
    {
        min_rgb = min(min_rgb, pixels[i].rgb);
        max_rgb = max(max_rgb, pixels[i].rgb);
    }

    // 2. Check for uniform block -> void extent
    float3 extent = max_rgb - min_rgb;
    float max_extent = max(extent.x, max(extent.y, extent.z));
    if (max_extent < (1.0f / 255.0f))
    {
        float4 avg = float4((min_rgb + max_rgb) * 0.5f, 1.0f);
        return astc_void_extent(avg);
    }

    // 3. Quantize endpoints to 8-bit
    uint endpoints[6];
    endpoints[0] = (uint)(saturate(min_rgb.r) * 255.0f + 0.5f);
    endpoints[1] = (uint)(saturate(max_rgb.r) * 255.0f + 0.5f);
    endpoints[2] = (uint)(saturate(min_rgb.g) * 255.0f + 0.5f);
    endpoints[3] = (uint)(saturate(max_rgb.g) * 255.0f + 0.5f);
    endpoints[4] = (uint)(saturate(min_rgb.b) * 255.0f + 0.5f);
    endpoints[5] = (uint)(saturate(max_rgb.b) * 255.0f + 0.5f);

    // 4. Compute weights: map 4x4 grid to 10x5 pixel block
    //    px = (gx * 9 + 1) / 3, py = (gy * 4 + 1) / 3
    float3 axis = max_rgb - min_rgb;
    float axis_len2 = dot(axis, axis);
    uint weights[16];

    [unroll]
    for (int gy = 0; gy < 4; gy++)
    {
        [unroll]
        for (int gx = 0; gx < 4; gx++)
        {
            uint px = ((uint)(gx) * 9u + 1u) / 3u;
            uint py = ((uint)(gy) * 4u + 1u) / 3u;
            uint pixel_idx = py * 10u + px;

            float3 color = pixels[pixel_idx].rgb;
            float t = dot(color - min_rgb, axis) / axis_len2;
            weights[gy * 4 + gx] = astc_quantize_weight_q4(t);
        }
    }

    // 5. Pack and return with correct block mode for 10x5
    return astc_pack_block_with_mode(ASTC_BLOCK_MODE_10x5_Q4, endpoints, weights);
}

#endif // COMPRESS_ASTC_10X5_HLSL
