#ifndef ASTC_4x4_HDR_HLSL
#define ASTC_4x4_HDR_HLSL

//=============================================================================
// ASTC 4x4 HDR Compression (Improved Quality)
//=============================================================================

#include "astc_hdr_improved.hlsl"

// Main entry point for HDR 4x4 compression
uint4 compress_astc_4x4_hdr(float4 pixels[16])
{
    // Use improved log-space HDR compression for better quality
    return astc_compress_4x4_hdr_improved(pixels);
}

#endif // ASTC_4x4_HDR_HLSL
