#ifndef ASTC_COMMON_HLSL
#define ASTC_COMMON_HLSL

//=============================================================================
// ASTC Common Utilities
// Shared helpers for all ASTC block size compressors
//=============================================================================

// Color Endpoint Mode constants
#define ASTC_CEM_LDR_RGB_DIRECT 8

// Block modes for all ASTC block sizes
// QUANT_4 (2 bits/weight), single plane encoding (d=0), encoding family 1 (h=0)
// Formula: blockmode = ((r>>1) & 0x3) | ((r&0x1) << 4) | ((a&0x3) << 5) | ((b&0x3) << 7) | (h << 9) | (d << 10)
// Where: r=4 (for weight_quantmethod=2), a=(Y_GRIDS-2)&0x3, b=(X_GRIDS-4)&0x3

#define ASTC_BLOCK_MODE_4x4_Q4    0x0042u
#define ASTC_BLOCK_MODE_5x4_Q4    0x00C2u
#define ASTC_BLOCK_MODE_5x5_Q4    0x00E2u
#define ASTC_BLOCK_MODE_6x5_Q4    0x0162u
#define ASTC_BLOCK_MODE_6x6_Q4    0x0102u
#define ASTC_BLOCK_MODE_8x5_Q4    0x0062u
#define ASTC_BLOCK_MODE_8x6_Q4    0x0002u
#define ASTC_BLOCK_MODE_8x8_Q4    0x0042u
#define ASTC_BLOCK_MODE_10x5_Q4   0x0162u
#define ASTC_BLOCK_MODE_10x6_Q4   0x0102u
#define ASTC_BLOCK_MODE_10x8_Q4   0x0142u
#define ASTC_BLOCK_MODE_10x10_Q4  0x0102u
#define ASTC_BLOCK_MODE_12x10_Q4  0x0002u
#define ASTC_BLOCK_MODE_12x12_Q4  0x0042u

//-----------------------------------------------------------------------------
// Bit manipulation
//-----------------------------------------------------------------------------

uint astc_reverse_bits_32(uint v)
{
    v = ((v >> 1u) & 0x55555555u) | ((v & 0x55555555u) << 1u);
    v = ((v >> 2u) & 0x33333333u) | ((v & 0x33333333u) << 2u);
    v = ((v >> 4u) & 0x0F0F0F0Fu) | ((v & 0x0F0F0F0Fu) << 4u);
    v = ((v >> 8u) & 0x00FF00FFu) | ((v & 0x00FF00FFu) << 8u);
    v = (v >> 16u) | (v << 16u);
    return v;
}

uint astc_reverse_byte(uint b)
{
    b = ((b & 0xF0u) >> 4u) | ((b & 0x0Fu) << 4u);
    b = ((b & 0xCCu) >> 2u) | ((b & 0x33u) << 2u);
    b = ((b & 0xAAu) >> 1u) | ((b & 0x55u) << 1u);
    return b;
}

//-----------------------------------------------------------------------------
// Void-extent block (constant color)
// Encodes a block where all pixels share the same color.
// Layout:
//   bits[8:0]   = 111111100 (void-extent marker)
//   bits[9]     = 0 (2D)
//   bits[10]    = 0 (LDR)
//   bits[11]    = 0 (reserved)
//   bits[63:12] = all 1s (don't-care extent coordinates)
//   bits[79:64] = R (UNORM16)
//   bits[95:80] = G (UNORM16)
//   bits[111:96]= B (UNORM16)
//   bits[127:112]= A (UNORM16)
//-----------------------------------------------------------------------------

uint4 astc_void_extent(float4 color)
{
    uint r = (uint)(saturate(color.r) * 65535.0f + 0.5f);
    uint g = (uint)(saturate(color.g) * 65535.0f + 0.5f);
    uint b = (uint)(saturate(color.b) * 65535.0f + 0.5f);
    uint a = (uint)(saturate(color.a) * 65535.0f + 0.5f);

    uint4 block;
    block.x = 0xFFFFF1FCu; // void-extent marker + extent coords (all 1s)
    block.y = 0xFFFFFFFFu; // extent coords continued (all 1s)
    block.z = r | (g << 16u);
    block.w = b | (a << 16u);
    return block;
}

//-----------------------------------------------------------------------------
// Weight quantization helper
// Maps interpolation parameter t in [0,1] to QUANT_4 weight [0,3]
// QUANT_4 actual weights: {0, 21, 43, 64}/64 = {0, 0.328, 0.672, 1.0}
// Using simple rounding: weight = round(t * 3) gives close-enough boundaries
//-----------------------------------------------------------------------------

uint astc_quantize_weight_q4(float t)
{
    float ft = saturate(t) * 3.0f;
    uint w = (uint)(ft + 0.5f);
    if (w > 3u) w = 3u;
    return w;
}

//-----------------------------------------------------------------------------
// Block assembly
// Packs header, 6 endpoint values (CEM 8: RGB Direct), and 16 weights
// into a 128-bit ASTC block.
//
// Layout:
//   bits[10:0]   = block mode (4x4 grid, QUANT_4, single plane)
//   bits[12:11]  = partition count - 1 = 0 (single partition)
//   bits[16:13]  = CEM (LDR RGB Direct = 8)
//   bits[64:17]  = endpoint data (6 x 8 = 48 bits, QUANT_256)
//   bits[95:65]  = unused (zeros)
//   bits[127:96] = weight data (16 x 2 = 32 bits, bit-reversed)
//
// Endpoint order: e0_r, e1_r, e0_g, e1_g, e0_b, e1_b
//-----------------------------------------------------------------------------

// Pack block with explicit block mode parameter
uint4 astc_pack_block_with_mode(uint block_mode, uint endpoints[6], uint weights[16])
{
    // Header: block_mode | partition_count | CEM
    uint header = block_mode
                | (0u << 11u)
                | ((uint)(ASTC_CEM_LDR_RGB_DIRECT) << 13u);

    // Pack endpoint values into 48-bit blob
    uint ep_lo = endpoints[0]
               | (endpoints[1] << 8u)
               | (endpoints[2] << 16u)
               | (endpoints[3] << 24u);
    uint ep_hi = endpoints[4]
               | (endpoints[5] << 8u);

    // Assemble block words
    uint4 block;
    block.x = header | (ep_lo << 17u);
    block.y = (ep_lo >> 15u) | (ep_hi << 17u);
    block.z = (ep_hi >> 15u);

    // Pack weight data: 16 weights x 2 bits, then bit-reverse for ASTC layout
    uint weight_bits = 0u;
    [unroll]
    for (int i = 0; i < 16; i++)
    {
        weight_bits |= (weights[i] & 3u) << ((uint)(i) * 2u);
    }
    block.w = astc_reverse_bits_32(weight_bits);

    return block;
}

// Legacy function for backward compatibility (4x4 default)
uint4 astc_pack_block(uint endpoints[6], uint weights[16])
{
    return astc_pack_block_with_mode(ASTC_BLOCK_MODE_4x4_Q4, endpoints, weights);
}

#endif // ASTC_COMMON_HLSL
