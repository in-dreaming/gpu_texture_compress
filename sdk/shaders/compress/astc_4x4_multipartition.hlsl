#ifndef ASTC_4x4_MULTIPARTITION_HLSL
#define ASTC_4x4_MULTIPARTITION_HLSL

//=============================================================================
// ASTC 4x4 Multi-Partition (DISABLED - empirical study, kept as reference)
//
// A full 2-partition encoder was implemented and tested for ASTC_4x4 with the
// maximum-fitting bit budget: QUANT_5 weights (5 levels) + QUANT_32 endpoints
// (5-bit direct binary). Result: cannot beat single-partition on natural images.
//
// Reason: single-partition uses QUANT_12 weights (12 levels) + QUANT_256 endpoints
// (8-bit direct), which provides much finer interpolation. The 2-partition path's
// extra spatial freedom (2x endpoint sets) does not compensate for the 8x coarser
// per-channel endpoint quantization that the 4x4 bit budget forces.
//
// 2-partition becomes more useful at LARGER block sizes (8x8, 10x10) where the
// per-pixel bit budget is tighter and partition splitting saves more variance.
// See experiments/programs/astc.md for future direction.
//=============================================================================

#include "astc_common.hlsl"

// Forward declaration (defined in astc_4x4.hlsl)
uint4 compress_astc_4x4_single(float4 pixels[16]);

// Stub: always returns single-partition encoding
uint4 compress_astc_4x4_multipartition(float4 pixels[16]) {
    return compress_astc_4x4_single(pixels);
}

#endif // ASTC_4x4_MULTIPARTITION_HLSL
