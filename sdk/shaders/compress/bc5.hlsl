// compress/bc5.hlsl - Pure BC5 compression function
// No global state, no texture reads.
// BC5 format: BC4 on red channel (64 bits) + BC4 on green channel (64 bits) = 128 bits
// Output: uint4(red_block.x, red_block.y, green_block.x, green_block.y)

#ifndef COMPRESS_BC5_HLSL
#define COMPRESS_BC5_HLSL

#include "compress/bc4.hlsl"

// Compress a 4x4 block of RG pixels into BC5 (128-bit block as uint4)
// .xy = red channel block (BC4)
// .zw = green channel block (BC4)
uint4 compress_bc5(float2 pixels[16]) {
    // Extract red channel
    float redValues[16];
    [unroll] for (int i = 0; i < 16; i++) {
        redValues[i] = pixels[i].x;
    }

    // Extract green channel
    float greenValues[16];
    [unroll] for (int j = 0; j < 16; j++) {
        greenValues[j] = pixels[j].y;
    }

    // Compress each channel independently with BC4
    uint2 redBlock = compress_bc4(redValues);
    uint2 greenBlock = compress_bc4(greenValues);

    // BC5 layout: red block first, then green block
    return uint4(redBlock.x, redBlock.y, greenBlock.x, greenBlock.y);
}

#endif // COMPRESS_BC5_HLSL
