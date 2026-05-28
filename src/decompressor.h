#pragma once

#include "texture_loader.h"
#include "../sdk/include/gtc_formats.h"
#include <vector>
#include <cstdint>

namespace gtc {

// CPU-side reference decompressor for quality evaluation
// These produce ground-truth decompressed images from compressed block data.
class Decompressor {
public:
    // Decompress any supported format back to RGBA8
    TextureData decompress(const uint8_t* data, uint32_t width, uint32_t height, GtcFormat format);

    // Individual format decompressors
    TextureData decompress_bc1(const uint8_t* data, uint32_t w, uint32_t h);
    TextureData decompress_bc3(const uint8_t* data, uint32_t w, uint32_t h);
    TextureData decompress_bc4(const uint8_t* data, uint32_t w, uint32_t h);
    TextureData decompress_bc5(const uint8_t* data, uint32_t w, uint32_t h);
    TextureData decompress_bc6h(const uint8_t* data, uint32_t w, uint32_t h);
    TextureData decompress_bc7(const uint8_t* data, uint32_t w, uint32_t h);
    TextureData decompress_astc(const uint8_t* data, uint32_t w, uint32_t h,
                                uint32_t block_x, uint32_t block_y);

private:
    // BC1: decode one 64-bit block to 4x4 RGBA8 pixels
    void decode_bc1_block(const uint8_t* block, uint8_t out[4 * 4 * 4]);
};

} // namespace gtc
