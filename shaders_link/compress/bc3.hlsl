// compress/bc3.hlsl - Pure BC3 compression function
// No global state, no texture reads.
// BC3 format: BC4 alpha block (64 bits) + BC1 color block (64 bits) = 128 bits
// Output: uint4(alpha_block.x, alpha_block.y, color_block.x, color_block.y)

#ifndef COMPRESS_BC3_HLSL
#define COMPRESS_BC3_HLSL

#include "compress/bc1.hlsl"
#include "compress/bc4.hlsl"

// Compress a 4x4 block of RGBA pixels into BC3 (128-bit block as uint4)
// .xy = alpha block (BC4 on alpha channel)
// .zw = color block (BC1 on RGB channels)
uint4 compress_bc3(float4 pixels[16]) {
    // Extract RGB for BC1 compression
    float3 rgbPixels[16];
    [unroll] for (int i = 0; i < 16; i++) {
        rgbPixels[i] = pixels[i].rgb;
    }

    // Extract alpha channel for BC4 compression
    float alphaValues[16];
    [unroll] for (int j = 0; j < 16; j++) {
        alphaValues[j] = pixels[j].a;
    }

    // Compress color with BC1
    uint2 colorBlock = compress_bc1(rgbPixels);

    // Compress alpha with BC4
    uint2 alphaBlock = compress_bc4(alphaValues);

    // BC3 layout: alpha block first, then color block
    return uint4(alphaBlock.x, alphaBlock.y, colorBlock.x, colorBlock.y);
}

#endif // COMPRESS_BC3_HLSL
