#include "decompressor.h"
#include <cstdio>
#include <cstring>
#include <cmath>
#include <algorithm>

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN

// Official decompression libraries
#include <astcenc.h>

// DirectXTex BC headers
#include <DirectXMath.h>
#include "BC.h"

using namespace DirectX;

namespace gtc {

// ============================================================================
// DirectXTex BC decompression wrapper
// ============================================================================

// Helper: convert 16 XMVECTOR (float4) to RGBA8 output
static void xmvector_to_rgba8(const XMVECTOR pixels[16], uint8_t out[64]) {
    for (int i = 0; i < 16; i++) {
        XMFLOAT4 f;
        XMStoreFloat4(&f, pixels[i]);
        auto clamp01 = [](float v) { return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v); };
        out[i * 4 + 0] = (uint8_t)(clamp01(f.x) * 255.0f + 0.5f);
        out[i * 4 + 1] = (uint8_t)(clamp01(f.y) * 255.0f + 0.5f);
        out[i * 4 + 2] = (uint8_t)(clamp01(f.z) * 255.0f + 0.5f);
        out[i * 4 + 3] = (uint8_t)(clamp01(f.w) * 255.0f + 0.5f);
    }
}

// Generic BCn block decompression using DirectXTex
typedef void (*BCDecodeFunc)(XMVECTOR*, const uint8_t*);

static TextureData decompress_bc_generic(const uint8_t* data, uint32_t w, uint32_t h,
                                         uint32_t block_bytes, BCDecodeFunc decode_fn) {
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
            const uint8_t* block = data + (size_t)block_index * block_bytes;

            XMVECTOR pixels[16];
            decode_fn(pixels, block);

            uint8_t decoded[64]; // 16 pixels × 4 channels
            xmvector_to_rgba8(pixels, decoded);

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

// ============================================================================
// ASTC decompression using astcenc
// ============================================================================

static TextureData decompress_astc_official(const uint8_t* data, uint32_t w, uint32_t h,
                                            uint32_t block_x, uint32_t block_y) {
    TextureData result;
    result.width = w;
    result.height = h;
    result.channels = 4;
    result.is_hdr = false;
    result.format = TexelFormat::RGBA8_UNORM;
    result.pixels.resize((size_t)w * h * 4);

    // Configure astcenc for decompression
    astcenc_config config;
    astcenc_error status = astcenc_config_init(
        ASTCENC_PRF_LDR_SRGB,    // profile
        block_x, block_y, 1,      // block dimensions
        ASTCENC_PRE_FASTEST,       // preset (doesn't matter for decompress)
        ASTCENC_FLG_DECOMPRESS_ONLY,  // flags: must set for decompress-only builds
        &config
    );

    if (status != ASTCENC_SUCCESS) {
        fprintf(stderr, "[Decompressor] ASTC config init failed: %d\n", (int)status);
        return result;
    }

    astcenc_context* context = nullptr;
    status = astcenc_context_alloc(&config, 1, &context, nullptr);
    if (status != ASTCENC_SUCCESS) {
        fprintf(stderr, "[Decompressor] ASTC context alloc failed: %d\n", (int)status);
        return result;
    }

    // Set up output image
    astcenc_image image;
    image.dim_x = w;
    image.dim_y = h;
    image.dim_z = 1;
    image.data_type = ASTCENC_TYPE_U8;
    uint8_t* slices[1] = { result.pixels.data() };
    image.data = reinterpret_cast<void**>(slices);

    // Compute data length
    uint32_t blocks_x_count = (w + block_x - 1) / block_x;
    uint32_t blocks_y_count = (h + block_y - 1) / block_y;
    size_t data_len = (size_t)blocks_x_count * blocks_y_count * 16;

    // Swizzle: RGBA identity
    astcenc_swizzle swizzle = { ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A };

    status = astcenc_decompress_image(context, data, data_len, &image, &swizzle, 0);
    if (status != ASTCENC_SUCCESS) {
        fprintf(stderr, "[Decompressor] ASTC decompress failed: %d\n", (int)status);
    }

    astcenc_context_free(context);
    return result;
}

// ============================================================================
// Public API
// ============================================================================

TextureData Decompressor::decompress(const uint8_t* data, uint32_t width, uint32_t height, GtcFormat format) {
    switch (format) {
        case GTC_FORMAT_BC1:  return decompress_bc1(data, width, height);
        case GTC_FORMAT_BC3:  return decompress_bc3(data, width, height);
        case GTC_FORMAT_BC4:  return decompress_bc4(data, width, height);
        case GTC_FORMAT_BC5:  return decompress_bc5(data, width, height);
        case GTC_FORMAT_BC6H: return decompress_bc6h(data, width, height);
        case GTC_FORMAT_BC7:  return decompress_bc7(data, width, height);
        // All ASTC formats
        case GTC_FORMAT_ASTC_4x4:   return decompress_astc(data, width, height, 4, 4);
        case GTC_FORMAT_ASTC_5x4:   return decompress_astc(data, width, height, 5, 4);
        case GTC_FORMAT_ASTC_5x5:   return decompress_astc(data, width, height, 5, 5);
        case GTC_FORMAT_ASTC_6x5:   return decompress_astc(data, width, height, 6, 5);
        case GTC_FORMAT_ASTC_6x6:   return decompress_astc(data, width, height, 6, 6);
        case GTC_FORMAT_ASTC_8x5:   return decompress_astc(data, width, height, 8, 5);
        case GTC_FORMAT_ASTC_8x6:   return decompress_astc(data, width, height, 8, 6);
        case GTC_FORMAT_ASTC_8x8:   return decompress_astc(data, width, height, 8, 8);
        case GTC_FORMAT_ASTC_10x5:  return decompress_astc(data, width, height, 10, 5);
        case GTC_FORMAT_ASTC_10x6:  return decompress_astc(data, width, height, 10, 6);
        case GTC_FORMAT_ASTC_10x8:  return decompress_astc(data, width, height, 10, 8);
        case GTC_FORMAT_ASTC_10x10: return decompress_astc(data, width, height, 10, 10);
        case GTC_FORMAT_ASTC_12x10: return decompress_astc(data, width, height, 12, 10);
        case GTC_FORMAT_ASTC_12x12: return decompress_astc(data, width, height, 12, 12);
        default: {
            TextureData empty;
            return empty;
        }
    }
}

// BCn implementations using DirectXTex
TextureData Decompressor::decompress_bc1(const uint8_t* data, uint32_t w, uint32_t h) {
    return decompress_bc_generic(data, w, h, 8, D3DXDecodeBC1);
}

TextureData Decompressor::decompress_bc3(const uint8_t* data, uint32_t w, uint32_t h) {
    return decompress_bc_generic(data, w, h, 16, D3DXDecodeBC3);
}

TextureData Decompressor::decompress_bc4(const uint8_t* data, uint32_t w, uint32_t h) {
    return decompress_bc_generic(data, w, h, 8, D3DXDecodeBC4U);
}

TextureData Decompressor::decompress_bc5(const uint8_t* data, uint32_t w, uint32_t h) {
    return decompress_bc_generic(data, w, h, 16, D3DXDecodeBC5U);
}

TextureData Decompressor::decompress_bc6h(const uint8_t* data, uint32_t w, uint32_t h) {
    return decompress_bc_generic(data, w, h, 16, D3DXDecodeBC6HU);
}

TextureData Decompressor::decompress_bc7(const uint8_t* data, uint32_t w, uint32_t h) {
    return decompress_bc_generic(data, w, h, 16, D3DXDecodeBC7);
}

// ASTC implementation using astcenc
TextureData Decompressor::decompress_astc(const uint8_t* data, uint32_t w, uint32_t h,
                                          uint32_t block_x, uint32_t block_y) {
    return decompress_astc_official(data, w, h, block_x, block_y);
}

// Legacy helpers (keep declaration in header satisfied)
void Decompressor::decode_bc1_block(const uint8_t* block, uint8_t out[4 * 4 * 4]) {
    XMVECTOR pixels[16];
    D3DXDecodeBC1(pixels, block);
    xmvector_to_rgba8(pixels, out);
}

void Decompressor::decode_bc4_block(const uint8_t* block, uint8_t out[16]) {
    XMVECTOR pixels[16];
    D3DXDecodeBC4U(pixels, block);
    for (int i = 0; i < 16; i++) {
        XMFLOAT4 f;
        XMStoreFloat4(&f, pixels[i]);
        float v = f.x < 0.0f ? 0.0f : (f.x > 1.0f ? 1.0f : f.x);
        out[i] = (uint8_t)(v * 255.0f + 0.5f);
    }
}

} // namespace gtc
