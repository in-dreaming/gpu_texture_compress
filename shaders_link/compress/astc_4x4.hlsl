// ASTC 4x4 Compression — GPU Texture Compression SDK
// Based on deps/astc_encoder (niepp/astc_encoder, MIT license)
// Production-quality baseline: PCA + QUANT_12 + ISE encoding

#ifndef COMPRESS_ASTC_4X4_HLSL
#define COMPRESS_ASTC_4X4_HLSL

#define BLOCK_6X6 0
#define HAS_ALPHA 0
#include "astc_encode_core.hlsl"

// Main entry: takes 16 RGBA pixels [0,1], returns 128-bit ASTC block
uint4 compress_astc_4x4(float4 pixels[16]) {
    float4 texels[BLOCK_SIZE];
    for (int i = 0; i < 16; i++) {
        texels[i] = pixels[i] * 255.0f;
    }
    return encode_block(texels);
}

#endif // COMPRESS_ASTC_4X4_HLSL
