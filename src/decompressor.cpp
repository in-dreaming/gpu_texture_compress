#include "decompressor.h"
#include <cstdio>
#include <cstring>
#include <cmath>

namespace gtc {

TextureData Decompressor::decompress(const uint8_t* data, uint32_t width, uint32_t height, GtcFormat format) {
    const auto& info = get_format_info(format);

    switch (format) {
        case GTC_FORMAT_BC1:  return decompress_bc1(data, width, height);
        case GTC_FORMAT_BC3:  return decompress_bc3(data, width, height);
        case GTC_FORMAT_BC4:  return decompress_bc4(data, width, height);
        case GTC_FORMAT_BC5:  return decompress_bc5(data, width, height);
        case GTC_FORMAT_BC6H: return decompress_bc6h(data, width, height);
        case GTC_FORMAT_BC7:  return decompress_bc7(data, width, height);
        case GTC_FORMAT_ASTC_4x4:  return decompress_astc(data, width, height, 4, 4);
        case GTC_FORMAT_ASTC_6x6:  return decompress_astc(data, width, height, 6, 6);
        case GTC_FORMAT_ASTC_8x8:  return decompress_astc(data, width, height, 8, 8);
        default: {
            TextureData empty;
            return empty;
        }
    }
}

// Decode RGB565 to float RGB
static void decode_rgb565(uint16_t color, uint8_t out[3]) {
    out[0] = (uint8_t)(((color >> 11) & 0x1F) * 255 / 31);
    out[1] = (uint8_t)(((color >> 5) & 0x3F) * 255 / 63);
    out[2] = (uint8_t)((color & 0x1F) * 255 / 31);
}

void Decompressor::decode_bc1_block(const uint8_t* block, uint8_t out[4 * 4 * 4]) {
    uint16_t c0 = block[0] | (block[1] << 8);
    uint16_t c1 = block[2] | (block[3] << 8);
    uint32_t indices = block[4] | (block[5] << 8) | (block[6] << 16) | (block[7] << 24);

    uint8_t color0[3], color1[3];
    decode_rgb565(c0, color0);
    decode_rgb565(c1, color1);

    uint8_t palette[4][4]; // RGBA
    palette[0][0] = color0[0]; palette[0][1] = color0[1]; palette[0][2] = color0[2]; palette[0][3] = 255;
    palette[1][0] = color1[0]; palette[1][1] = color1[1]; palette[1][2] = color1[2]; palette[1][3] = 255;

    if (c0 > c1) {
        // 4-color mode
        palette[2][0] = (uint8_t)((2 * color0[0] + color1[0] + 1) / 3);
        palette[2][1] = (uint8_t)((2 * color0[1] + color1[1] + 1) / 3);
        palette[2][2] = (uint8_t)((2 * color0[2] + color1[2] + 1) / 3);
        palette[2][3] = 255;
        palette[3][0] = (uint8_t)((color0[0] + 2 * color1[0] + 1) / 3);
        palette[3][1] = (uint8_t)((color0[1] + 2 * color1[1] + 1) / 3);
        palette[3][2] = (uint8_t)((color0[2] + 2 * color1[2] + 1) / 3);
        palette[3][3] = 255;
    } else {
        // 3-color + transparent mode
        palette[2][0] = (uint8_t)((color0[0] + color1[0]) / 2);
        palette[2][1] = (uint8_t)((color0[1] + color1[1]) / 2);
        palette[2][2] = (uint8_t)((color0[2] + color1[2]) / 2);
        palette[2][3] = 255;
        palette[3][0] = 0; palette[3][1] = 0; palette[3][2] = 0; palette[3][3] = 0;
    }

    for (int i = 0; i < 16; i++) {
        uint32_t idx = (indices >> (i * 2)) & 0x3;
        out[i * 4 + 0] = palette[idx][0];
        out[i * 4 + 1] = palette[idx][1];
        out[i * 4 + 2] = palette[idx][2];
        out[i * 4 + 3] = palette[idx][3];
    }
}

TextureData Decompressor::decompress_bc1(const uint8_t* data, uint32_t w, uint32_t h) {
    TextureData result;
    result.width = w;
    result.height = h;
    result.channels = 4;
    result.is_hdr = false;
    result.format = TexelFormat::RGBA8_UNORM;
    result.pixels.resize((size_t)w * h * 4);

    uint32_t blocks_x = (w + 3) / 4;
    uint32_t blocks_y = (h + 3) / 4;

    for (uint32_t by = 0; by < blocks_y; by++) {
        for (uint32_t bx = 0; bx < blocks_x; bx++) {
            uint32_t block_index = by * blocks_x + bx;
            const uint8_t* block = data + block_index * 8; // BC1 = 8 bytes per block

            uint8_t decoded[4 * 4 * 4]; // 16 pixels * 4 channels
            decode_bc1_block(block, decoded);

            // Write decoded pixels to output image
            for (int py = 0; py < 4; py++) {
                for (int px = 0; px < 4; px++) {
                    uint32_t img_x = bx * 4 + px;
                    uint32_t img_y = by * 4 + py;
                    if (img_x >= w || img_y >= h) continue;

                    uint32_t src_offset = (py * 4 + px) * 4;
                    uint32_t dst_offset = (img_y * w + img_x) * 4;
                    result.pixels[dst_offset + 0] = decoded[src_offset + 0];
                    result.pixels[dst_offset + 1] = decoded[src_offset + 1];
                    result.pixels[dst_offset + 2] = decoded[src_offset + 2];
                    result.pixels[dst_offset + 3] = decoded[src_offset + 3];
                }
            }
        }
    }

    return result;
}

// Stub implementations for other formats (to be filled in later)
TextureData Decompressor::decompress_bc3(const uint8_t* data, uint32_t w, uint32_t h) {
    // TODO: Implement BC3 decompression (BC1 color + BC4 alpha)
    TextureData result;
    result.width = w; result.height = h; result.channels = 4;
    result.pixels.resize((size_t)w * h * 4, 128);
    printf("[Decompressor] WARNING: BC3 decompression not yet implemented\n");
    return result;
}

TextureData Decompressor::decompress_bc4(const uint8_t* data, uint32_t w, uint32_t h) {
    // TODO: Implement BC4 decompression (single channel)
    TextureData result;
    result.width = w; result.height = h; result.channels = 4;
    result.pixels.resize((size_t)w * h * 4, 128);
    printf("[Decompressor] WARNING: BC4 decompression not yet implemented\n");
    return result;
}

TextureData Decompressor::decompress_bc5(const uint8_t* data, uint32_t w, uint32_t h) {
    // TODO: Implement BC5 decompression (two channels)
    TextureData result;
    result.width = w; result.height = h; result.channels = 4;
    result.pixels.resize((size_t)w * h * 4, 128);
    printf("[Decompressor] WARNING: BC5 decompression not yet implemented\n");
    return result;
}

TextureData Decompressor::decompress_bc6h(const uint8_t* data, uint32_t w, uint32_t h) {
    // TODO: Implement BC6H decompression (HDR)
    TextureData result;
    result.width = w; result.height = h; result.channels = 4;
    result.pixels.resize((size_t)w * h * 4, 128);
    printf("[Decompressor] WARNING: BC6H decompression not yet implemented\n");
    return result;
}

TextureData Decompressor::decompress_bc7(const uint8_t* data, uint32_t w, uint32_t h) {
    // TODO: Implement BC7 decompression (8 modes)
    TextureData result;
    result.width = w; result.height = h; result.channels = 4;
    result.pixels.resize((size_t)w * h * 4, 128);
    printf("[Decompressor] WARNING: BC7 decompression not yet implemented\n");
    return result;
}

TextureData Decompressor::decompress_astc(const uint8_t* data, uint32_t w, uint32_t h,
                                          uint32_t block_x, uint32_t block_y) {
    // TODO: Implement ASTC decompression
    TextureData result;
    result.width = w; result.height = h; result.channels = 4;
    result.pixels.resize((size_t)w * h * 4, 128);
    printf("[Decompressor] WARNING: ASTC %ux%u decompression not yet implemented\n", block_x, block_y);
    return result;
}

} // namespace gtc
