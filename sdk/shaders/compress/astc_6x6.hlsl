// ASTC 6x6 Compression — GPU Texture Compression SDK
// Based on deps/astc_encoder (niepp/astc_encoder, MIT license)
// Production-quality baseline: PCA + bilinear grid mapping + QUANT_12 + ISE

#ifndef COMPRESS_ASTC_6X6_HLSL
#define COMPRESS_ASTC_6X6_HLSL

#define BLOCK_6X6 1
#define HAS_ALPHA 0
#include "astc_encode_core.hlsl"

// Main entry: takes 36 RGBA pixels [0,1], returns 128-bit ASTC block
uint4 compress_astc_6x6(float4 pixels[36]) {
    float4 texels[BLOCK_SIZE];
    for (int i = 0; i < 36; i++) {
        texels[i] = pixels[i] * 255.0f;
    }
    return encode_block(texels);
}

#endif // COMPRESS_ASTC_6X6_HLSL
