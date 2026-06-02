#ifndef ASTC_4x4_HDR_HLSL
#define ASTC_4x4_HDR_HLSL

//=============================================================================
// ASTC 4x4 HDR Compression — full CEM 12 (HDR RGB Direct) encoder
// Implements all 8 precision modes + flat fallback per ASTC spec.
//=============================================================================

#include "astc_hdr_proper.hlsl"

uint4 compress_astc_4x4_hdr(float4 pixels[16])
{
    return astc_compress_4x4_hdr_proper(pixels);
}

#endif // ASTC_4x4_HDR_HLSL
