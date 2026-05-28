// compress/bc1.hlsl - Pure BC1 compression function
// No global state, no texture reads. Takes 16 RGB pixels, returns packed 64-bit block.
// BC1 format: 2x RGB565 endpoints (32 bits) + 16x 2-bit indices (32 bits)

#ifndef COMPRESS_BC1_HLSL
#define COMPRESS_BC1_HLSL

#include "common/endpoint_fit.hlsl"

// Encode float RGB [0,1] to RGB565
uint EncodeRGB565(float3 color) {
    color = saturate(color);
    uint r = (uint)(color.r * 31.0 + 0.5);
    uint g = (uint)(color.g * 63.0 + 0.5);
    uint b = (uint)(color.b * 31.0 + 0.5);
    return (r << 11) | (g << 5) | b;
}

// Decode RGB565 to float RGB [0,1]
float3 DecodeRGB565(uint packed) {
    float r = (float)((packed >> 11) & 0x1F) / 31.0;
    float g = (float)((packed >> 5) & 0x3F) / 63.0;
    float b = (float)(packed & 0x1F) / 31.0;
    return float3(r, g, b);
}

// Compress a 4x4 block of RGB pixels into BC1 (64-bit block as uint2)
// .x = ep0_565 | (ep1_565 << 16)
// .y = 32 bits of 2-bit indices (pixel 0 in LSBs)
uint2 compress_bc1(float3 pixels[16]) {
    // Compute mean color
    float3 mean = float3(0, 0, 0);
    [unroll] for (int i = 0; i < 16; i++) {
        mean += pixels[i];
    }
    mean /= 16.0;

    // PCA: compute principal axis via power iteration
    float3 axis = ComputePCAAxis(pixels, mean);

    // Project pixels onto axis to find endpoint positions
    float minProj, maxProj;
    ProjectOntoAxis(pixels, mean, axis, minProj, maxProj);

    // Compute endpoints from projection extremes
    float3 endpoint0 = saturate(mean + axis * maxProj);
    float3 endpoint1 = saturate(mean + axis * minProj);

    // Inset endpoints slightly to reduce palette boundary error
    endpoint0 = lerp(mean, endpoint0, 6.0 / 7.0);
    endpoint1 = lerp(mean, endpoint1, 6.0 / 7.0);

    // Quantize to RGB565
    uint ep0_565 = EncodeRGB565(endpoint0);
    uint ep1_565 = EncodeRGB565(endpoint1);

    // Ensure ep0 > ep1 for 4-color mode (BC1 specification)
    if (ep0_565 < ep1_565) {
        uint tmp = ep0_565;
        ep0_565 = ep1_565;
        ep1_565 = tmp;
        float3 tmpf = endpoint0;
        endpoint0 = endpoint1;
        endpoint1 = tmpf;
    }

    // Handle degenerate case (same endpoints) - all indices zero
    if (ep0_565 == ep1_565) {
        return uint2(ep0_565 | (ep1_565 << 16), 0);
    }

    // Reconstruct quantized endpoints for accurate index assignment
    float3 qep0 = DecodeRGB565(ep0_565);
    float3 qep1 = DecodeRGB565(ep1_565);

    // Generate 4-color palette
    float3 palette[4];
    palette[0] = qep0;
    palette[1] = qep1;
    palette[2] = (2.0 / 3.0) * qep0 + (1.0 / 3.0) * qep1;
    palette[3] = (1.0 / 3.0) * qep0 + (2.0 / 3.0) * qep1;

    // Assign each pixel to the closest palette entry
    uint indices = 0;
    [unroll] for (int pi = 0; pi < 16; pi++) {
        float bestDist = 1e10;
        uint bestIdx = 0;
        [unroll] for (int j = 0; j < 4; j++) {
            float3 diff = pixels[pi] - palette[j];
            float dist = dot(diff, diff);
            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = j;
            }
        }
        indices |= (bestIdx << (pi * 2));
    }

    // Pack: endpoints in .x, indices in .y
    return uint2(ep0_565 | (ep1_565 << 16), indices);
}

#endif // COMPRESS_BC1_HLSL
