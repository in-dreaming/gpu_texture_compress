// ASTC 6x6: 5x5 weight grid encoder (PoC for variable-grid path).
// Replaces the 4x4-grid-via-subsample path used previously.
//
// Encoder pipeline:
//   1. Take all 36 input pixels at full resolution (no subsampling).
//   2. PCA on 36 texels for endpoint axis.
//   3. Decimate to 25 grid samples via bilinear (decimation table in
//      astc_encode_grid5x5.hlsl), project onto axis, normalize.
//   4. Quantize to QUANT_5 (5 levels), ISE-pack as 9 quint groups.
//   5. Pack into 128-bit block with mode 242 (5x5 grid + Q5 weights).

#ifndef COMPRESS_ASTC_6X6_HLSL
#define COMPRESS_ASTC_6X6_HLSL

#include "astc_encode_grid5x5.hlsl"

uint4 compress_astc_6x6(float4 pixels[36])
{
    float4 texels[36];
    [unroll] for (int i = 0; i < 36; i++) {
        texels[i] = pixels[i] * 255.0f;
    }
    return encode_block_5x5_in_6x6(texels);
}

#endif // COMPRESS_ASTC_6X6_HLSL
