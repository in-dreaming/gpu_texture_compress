// compress/astc.hlsl - Pure ASTC compression function
// No global state, no texture reads. Takes WxH RGBA pixels, returns packed 128-bit block.
// ASTC_BLOCK_W and ASTC_BLOCK_H must be #defined before including this file.
// Supports all 14 standard ASTC block sizes (4x4 through 12x12).
//
// Baseline implementation: single partition, CEM 8 (LDR RGB Direct),
// 4x4 weight grid with QUANT_4 (range 0-3). Falls back to void-extent
// (constant color) for uniform blocks.

#ifndef COMPRESS_ASTC_HLSL
#define COMPRESS_ASTC_HLSL

// ============================================================================
// ASTC Void-Extent Block Encoding
// ============================================================================
// A void-extent block encodes a single constant RGBA color for the entire block.
// Layout (128 bits):
//   bits [8:0]   = 0x1FC (void-extent 2D marker: bits[1:0]=00, bits[8:2]=1111111)
//   bit  [9]     = 1 (2D texture)
//   bits [11:10] = 11 (reserved/don't-care extents)
//   bits [63:12] = extent coords, all 1s = full range
//   bits [79:64] = R (16-bit UNORM)
//   bits [95:80] = G (16-bit UNORM)
//   bits [111:96] = B (16-bit UNORM)
//   bits [127:112] = A (16-bit UNORM)

uint4 astc_encode_void_extent(float4 color) {
    uint4 block;

    // Lower 64 bits: void-extent marker + all-1 extent coordinates
    // bits[11:0] = 0xFFC (marker + 2D flag + don't-care extents)
    // bits[63:12] = all 1s (13-bit extent fields all set to 0x1FFF)
    block.x = 0xFFFFFFFCu;
    block.y = 0xFFFFFFFFu;

    // Upper 64 bits: RGBA as 16-bit UNORM values
    uint R = (uint)(saturate(color.r) * 65535.0f + 0.5f);
    uint G = (uint)(saturate(color.g) * 65535.0f + 0.5f);
    uint B = (uint)(saturate(color.b) * 65535.0f + 0.5f);
    uint A = (uint)(saturate(color.a) * 65535.0f + 0.5f);

    block.z = R | (G << 16u);
    block.w = B | (A << 16u);

    return block;
}

// ============================================================================
// ASTC Block Mode Encoding (Baseline: 4x4 grid, QUANT_4, single plane)
// ============================================================================
// Block mode bits[10:0] for 4x4 weight grid, quantization range 0-3, single plane:
//   Sub-mode 0 (bits[3:2] = 00): Width = A+4, Height = B+2
//   For Width=4: A=0 (bits[8:7]=00), Height=4: B=2 (bits[6:5]=10)
//   QUANT_4 → range_index=4 → R2R1R0=010, H=0
//   R0=bit[0]=0, R1=bit[1]=1, R2=bit[4]=0
//   D=bit[10]=0, H=bit[9]=0
//   Result: 0b00001000010 = 0x042
#define ASTC_BLOCK_MODE_4x4_Q4  0x042u

// Partition count - 1 = 0 (single partition), stored in bits[12:11]
#define ASTC_PARTITION_SINGLE    0u

// CEM 8 = LDR RGB Direct (6 endpoint values: R0,R1,G0,G1,B0,B1, alpha=255)
#define ASTC_CEM_LDR_RGB_DIRECT  8u

// ============================================================================
// Weight Packing
// ============================================================================
// ASTC weights are stored from bit 127 downward with bit-reversal:
// The weight bitstream is encoded normally, then the entire stream is
// bit-reversed and placed at the MSB end of the 128-bit block.
// For QUANT_4 (range 0-3, 2 bits each), 4x4 grid = 16 weights = 32 bits.
// Stored in block.w (bits [127:96]).

uint astc_pack_weights_4x4_q4(uint weights[16]) {
    uint packed = 0u;

    // Each weight is 2 bits. After bit-reversal of the stream:
    // bit 127 = weight[0] LSB, bit 126 = weight[0] MSB,
    // bit 125 = weight[1] LSB, bit 124 = weight[1] MSB, ...
    [unroll] for (int i = 0; i < 16; i++) {
        uint w = min(weights[i], 3u);
        uint lsb = w & 1u;
        uint msb = (w >> 1u) & 1u;
        packed |= (lsb << (uint)(31 - 2 * i));
        packed |= (msb << (uint)(30 - 2 * i));
    }

    return packed;
}

// ============================================================================
// Endpoint Packing
// ============================================================================
// With 4x4 QUANT_4 weights (32 bits) and 17-bit header, we have:
//   128 - 32 - 17 = 79 bits for endpoints.
// For CEM 8 with 6 values, the decoder selects range 255 (8 bits each = 48 bits).
// Endpoint order for CEM 8: v0=e0.R, v1=e1.R, v2=e0.G, v3=e1.G, v4=e0.B, v5=e1.B
// where e0 = (v0, v2, v4, 255) and e1 = (v1, v3, v5, 255).

// Packs header + endpoints into block.x, block.y, block.z (lower 96 bits).
// block.w is reserved for weight data.
void astc_pack_header_endpoints(out uint4 block, uint3 ep0, uint3 ep1) {
    // Header: bits[10:0]=mode, bits[12:11]=partition, bits[16:13]=CEM
    uint header = ASTC_BLOCK_MODE_4x4_Q4
               | (ASTC_PARTITION_SINGLE << 11u)
               | (ASTC_CEM_LDR_RGB_DIRECT << 13u);
    // header = 0x042 | 0 | 0x10000 = 0x10042

    // Endpoint data: 6 values × 8 bits = 48 bits, starting at bit 17
    // Pack as two uint values (ep_lo: 32 bits, ep_hi: 16 bits)
    uint ep_lo = (ep0.r & 0xFFu)
              | ((ep1.r & 0xFFu) << 8u)
              | ((ep0.g & 0xFFu) << 16u)
              | ((ep1.g & 0xFFu) << 24u);

    uint ep_hi = (ep0.b & 0xFFu)
              | ((ep1.b & 0xFFu) << 8u);

    // Place header at bits [16:0] and endpoints starting at bit 17
    block.x = header | (ep_lo << 17u);
    block.y = (ep_lo >> 15u) | (ep_hi << 17u);
    block.z = (ep_hi >> 15u);
    block.w = 0u; // Will be filled with weight data
}

// ============================================================================
// Main Compression Function
// ============================================================================
// Compress a block of pixels into a 128-bit ASTC block.
// pixels:      array of RGBA values, length = ASTC_BLOCK_W * ASTC_BLOCK_H (max 144)
// pixel_count: number of pixels (must equal ASTC_BLOCK_W * ASTC_BLOCK_H)
// Returns:     128-bit packed ASTC block as uint4

uint4 compress_astc(float4 pixels[ASTC_BLOCK_W * ASTC_BLOCK_H], uint pixel_count) {
    // ---- Step 1: Compute bounding box (min/max RGB) and average alpha ----
    float3 min_rgb = pixels[0].rgb;
    float3 max_rgb = pixels[0].rgb;
    float sum_a = pixels[0].a;

    [unroll] for (uint i = 1u; i < (uint)(ASTC_BLOCK_W * ASTC_BLOCK_H); i++) {
        min_rgb = min(min_rgb, pixels[i].rgb);
        max_rgb = max(max_rgb, pixels[i].rgb);
        sum_a += pixels[i].a;
    }

    float avg_a = sum_a / (float)(ASTC_BLOCK_W * ASTC_BLOCK_H);

    // ---- Step 2: Check for uniform block ----
    float3 axis = max_rgb - min_rgb;
    float axis_len_sq = dot(axis, axis);

    if (axis_len_sq < 1.0e-5f) {
        // Block is effectively a single color — use void-extent encoding
        float4 avg_color = float4((min_rgb + max_rgb) * 0.5f, avg_a);
        return astc_encode_void_extent(avg_color);
    }

    // ---- Step 3: Quantize endpoints to 8-bit ----
    uint3 ep0 = uint3(
        (uint)(saturate(min_rgb.r) * 255.0f + 0.5f),
        (uint)(saturate(min_rgb.g) * 255.0f + 0.5f),
        (uint)(saturate(min_rgb.b) * 255.0f + 0.5f)
    );
    uint3 ep1 = uint3(
        (uint)(saturate(max_rgb.r) * 255.0f + 0.5f),
        (uint)(saturate(max_rgb.g) * 255.0f + 0.5f),
        (uint)(saturate(max_rgb.b) * 255.0f + 0.5f)
    );

    // Ensure ep0 <= ep1 per channel (required for correct decode with CEM 8)
    uint3 lo = min(ep0, ep1);
    uint3 hi = max(ep0, ep1);
    ep0 = lo;
    ep1 = hi;

    // ---- Step 4: Compute 4x4 weight grid ----
    // Map each weight grid position to a pixel via nearest-neighbor sampling,
    // then project pixel color onto the endpoint axis to get interpolation weight.
    uint weights[16];
    float inv_axis_len_sq = 1.0f / axis_len_sq;

    [unroll] for (int gy = 0; gy < 4; gy++) {
        [unroll] for (int gx = 0; gx < 4; gx++) {
            // Map grid position [0..3] to pixel coordinate [0..block_dim-1]
            int px = (gx * ((int)ASTC_BLOCK_W - 1) + 1) / 3;
            int py = (gy * ((int)ASTC_BLOCK_H - 1) + 1) / 3;
            px = min(max(px, 0), (int)ASTC_BLOCK_W - 1);
            py = min(max(py, 0), (int)ASTC_BLOCK_H - 1);

            float3 color = pixels[py * ASTC_BLOCK_W + px].rgb;

            // Project onto min→max axis, result in [0, 1]
            float t = dot(color - min_rgb, axis) * inv_axis_len_sq;
            t = saturate(t);

            // Quantize to QUANT_4 range [0, 3]
            weights[gy * 4 + gx] = (uint)(t * 3.0f + 0.5f);
        }
    }

    // ---- Step 5: Pack the ASTC block ----
    uint4 block;
    astc_pack_header_endpoints(block, ep0, ep1);
    block.w = astc_pack_weights_4x4_q4(weights);

    return block;
}

#endif // COMPRESS_ASTC_HLSL
