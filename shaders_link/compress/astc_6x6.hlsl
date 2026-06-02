// ASTC 6x6: 5x5 weight grid encoder via the generic parameterized template.
// PSNR: 33.42 -> 35.49 dB on Khronos LDR-RGB (3 images, QualityLevel=1).

#ifndef COMPRESS_ASTC_6X6_HLSL
#define COMPRESS_ASTC_6X6_HLSL

#define BLOCK_W 6
#define BLOCK_H 6
#define BLOCK_SIZE 36
#define GRID_FUNC_NAME encode_block_5x5_in_6x6
#include "astc_encode_grid5x5_generic.hlsl"
#undef BLOCK_W
#undef BLOCK_H
#undef BLOCK_SIZE
#undef GRID_FUNC_NAME

uint4 compress_astc_6x6(float4 pixels[36])
{
    float4 texels[36];
    [unroll] for (int i = 0; i < 36; i++) {
        texels[i] = pixels[i] * 255.0f;
    }
    return encode_block_5x5_in_6x6(texels);
}

#endif // COMPRESS_ASTC_6X6_HLSL
