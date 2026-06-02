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

// QUANT_8 (3 bits/weight, 8 levels) block modes: same a/b grid encoding, R changes.
// For QUANT_8 (weight_quantmethod=5): r=7, so bits[1:0]=11, bit[4]=1.
// 4x4 grid contribution = bits[6:5]=10 = 0x40 -> mode = 0x40 + 0x10 + 0x03 = 0x53.
#define ASTC_BLOCK_MODE_4x4_Q8    0x0053u
#define ASTC_BLOCK_MODE_8x8_Q8    0x0053u   // 8x8 block, 4x4 grid, QUANT_8

// QUANT_12 block modes (12 weight levels via trit-ISE encoding, ~3.6 bits/weight)
// weight_quantmethod=7: r = (7%6)+2 = 3 -> bits[1:0]=01, bit[4]=1
// h = (7<6)?0:1 = 1
// 4x4 grid: a=2, b=0 -> bits[6:5]=10, bits[8:7]=00
// mode = 0x01 + 0x10 + 0x40 + 0x200 = 0x251
#define ASTC_BLOCK_MODE_4x4_Q12   0x0251u

// Larger weight grids + QUANT_8.
// Formula: r=7 (Q8) -> bits[1:0]=11, bit[4]=1, h=0.
//   5x4 grid: a=(Y-2)=2, b=(X-4)=1 -> bits[6:5]=10, bits[8:7]=01 -> 0x03+0x10+0x40+0x80 = 0xD3
//   4x5 grid: a=(Y-2)=3, b=(X-4)=0 -> bits[6:5]=11, bits[8:7]=00 -> 0x03+0x10+0x60+0x00 = 0x73
#define ASTC_BLOCK_MODE_5x4_Q8    0x00D3u  // 5 wide × 4 tall weight grid (20 weights)
#define ASTC_BLOCK_MODE_4x5_Q8    0x0073u  // 4 wide × 5 tall weight grid (20 weights)
// For 4x4 grid: only one value (0x53). Other grids would need different a/b.

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

// QUANT_8: 8 levels (3 bits per weight), decoded values {0, 9, 18, 28, 37, 46, 55, 64}/64
// For simple rounding: w = round(t * 7), boundaries close enough for typical data.
uint astc_quantize_weight_q8(float t)
{
    float ft = saturate(t) * 7.0f;
    uint w = (uint)(ft + 0.5f);
    if (w > 7u) w = 7u;
    return w;
}

// QUANT_12: 12 levels (~3.58 bits avg via ISE trit encoding).
// Decoded values {0, 6, 11, 17, 23, 28, 34, 40, 45, 51, 57, 64}/64.
// Approximate boundaries via simple rounding for performance: w = round(t * 11).
uint astc_quantize_weight_q12(float t)
{
    float ft = saturate(t) * 11.0f;
    uint w = (uint)(ft + 0.5f);
    if (w > 11u) w = 11u;
    return w;
}

//-----------------------------------------------------------------------------
// PCA-based endpoint selection (template-style, compile-time pixel count)
// Returns: min_rgb, max_rgb along principal axis (NOT channel-independent bbox)
// For correlated channel data, this gives much better endpoints than bbox.
//-----------------------------------------------------------------------------

// Compute principal axis via 8 power iterations on the 3x3 covariance matrix.
float3 astc_compute_pca_axis(float3 mean, float3 cov_diag, float3 cov_off)
{
    // cov_diag = (cov_xx, cov_yy, cov_zz)
    // cov_off  = (cov_xy, cov_xz, cov_yz)
    // Power iteration: v <- M * v / |M*v|
    float3 v = float3(0.5774, 0.5774, 0.5774);  // arbitrary unit vector
    [unroll] for (int it = 0; it < 8; it++) {
        float3 mv = float3(
            cov_diag.x * v.x + cov_off.x * v.y + cov_off.y * v.z,
            cov_off.x * v.x + cov_diag.y * v.y + cov_off.z * v.z,
            cov_off.y * v.x + cov_off.z * v.y + cov_diag.z * v.z
        );
        float l = length(mv);
        v = (l > 1e-6) ? (mv / l) : v;
    }
    return v;
}

// Project rgb onto axis; return signed projection.
float astc_project(float3 rgb, float3 mean, float3 axis) {
    return dot(rgb - mean, axis);
}

//-----------------------------------------------------------------------------
// LSQ endpoint refinement helpers (8-bit endpoints, continuous space).
// Solves the 2x2 normal equations for ep0, ep1 minimizing
//   sum_i || pixel_i - ((1-t_i)*ep0 + t_i*ep1) ||^2
// where t_i in [0,1] is the post-quantization weight for pixel i.
//-----------------------------------------------------------------------------

// Compute total squared error for current endpoints + per-pixel t values.
// Used by error-guarded LSQ to revert refinements that would worsen quality.
float astc_lsq_error_const(float3 ep0, float3 ep1, const uint N,
                            float t_arr[144], float3 pix_arr[144])
{
    float total = 0.0;
    for (uint i = 0u; i < N; i++) {
        float t = t_arr[i];
        float3 reconstructed = lerp(ep0, ep1, t);
        float3 d = pix_arr[i] - reconstructed;
        total += dot(d, d);
    }
    return total;
}

// Solve 2x2 LSQ given pre-projected pixels and their weights t in [0,1].
// On output, ep0/ep1 are continuous-space endpoints in [0..1] RGB space.
// Returns true if a meaningful solution was found, false on degenerate input.
bool astc_lsq_solve(const uint N, float t_arr[144], float3 pix_arr[144],
                     out float3 ep0_out, out float3 ep1_out)
{
    float A = 0.0, B = 0.0, C = 0.0;
    float3 X = float3(0,0,0), Y = float3(0,0,0);
    for (uint i = 0u; i < N; i++) {
        float t = t_arr[i];
        float u = 1.0 - t;
        A += u * u;
        B += u * t;
        C += t * t;
        X += pix_arr[i] * u;
        Y += pix_arr[i] * t;
    }
    float det = A * C - B * B;
    if (abs(det) < 1e-6) {
        ep0_out = float3(0,0,0);
        ep1_out = float3(0,0,0);
        return false;
    }
    float invDet = 1.0 / det;
    ep0_out = saturate((C * X - B * Y) * invDet);
    ep1_out = saturate((A * Y - B * X) * invDet);
    return true;
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

// Pack block with HDR CEM (CEM 11 = HDR RGB Direct, FMT_HDR_RGB).
// Per ASTC spec, CEM 11 uses 6 endpoint values (a, c, b0, b1, d0, d1) which
// the decoder unpacks via the HDR RGB direct path.
// Total endpoint bits: 6 × 8 = 48 bits at QUANT_256.
//
// Note: CEM 12 is LDR RGBA (FMT_RGBA), CEM 11 is HDR RGB Direct.
// astcenc enum: FMT_HDR_RGB = 11, FMT_RGBA = 12.
uint4 astc_pack_block_with_mode_hdr(uint block_mode, uint endpoints[6], uint weights[16])
{
    // Header: block_mode | partition_count=0 | CEM 11 (HDR RGB Direct)
    uint header = block_mode
                | (0u << 11u)
                | (11u << 13u);

    uint ep_lo = endpoints[0]
               | (endpoints[1] << 8u)
               | (endpoints[2] << 16u)
               | (endpoints[3] << 24u);
    uint ep_hi = endpoints[4]
               | (endpoints[5] << 8u);

    uint4 block;
    block.x = header | (ep_lo << 17u);
    block.y = (ep_lo >> 15u) | (ep_hi << 17u);
    block.z = (ep_hi >> 15u);

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

//-----------------------------------------------------------------------------
// QUANT_8 pack: 16 weights × 3 bits = 48 bits. Bit-reversed at end of block.
// Block bit 127 = stream bit 0 = weight[0] bit 0,
// Block bit 126 = stream bit 1 = weight[0] bit 1, ...
// Block bit 80  = stream bit 47 = weight[15] bit 2.
// Bit-by-bit assembly avoids tricky 48-bit reversal arithmetic.
//-----------------------------------------------------------------------------
uint4 astc_pack_block_q8(uint block_mode, uint endpoints[6], uint weights[16])
{
    // Header same as Q4 path
    uint header = block_mode
                | (0u << 11u)
                | ((uint)(ASTC_CEM_LDR_RGB_DIRECT) << 13u);

    uint ep_lo = endpoints[0]
               | (endpoints[1] << 8u)
               | (endpoints[2] << 16u)
               | (endpoints[3] << 24u);
    uint ep_hi = endpoints[4]
               | (endpoints[5] << 8u);

    uint4 block;
    block.x = header | (ep_lo << 17u);
    block.y = (ep_lo >> 15u) | (ep_hi << 17u);

    // Bit-by-bit assembly of weight area (block bits 80-127, bit-reversed).
    uint bz_high16 = 0u;  // block.z bits 16-31 = block bits 80-95
    uint bw = 0u;         // block.w bits 0-31 = block bits 96-127
    [unroll]
    for (int i = 0; i < 16; i++) {
        uint w = weights[i] & 7u;
        [unroll] for (int b = 0; b < 3; b++) {
            uint w_bit = (w >> (uint)b) & 1u;
            uint stream_pos = (uint)i * 3u + (uint)b;        // 0..47
            uint block_pos = 127u - stream_pos;              // 80..127
            if (block_pos >= 96u) {
                bw |= w_bit << (block_pos - 96u);
            } else {
                bz_high16 |= w_bit << (block_pos - 80u);
            }
        }
    }

    block.z = (ep_hi >> 15u) | (bz_high16 << 16u);
    block.w = bw;
    return block;
}

//-----------------------------------------------------------------------------
// QUANT_8 pack for 20-weight grids (5x4 or 4x5): 20 × 3 = 60 bits.
// Weight stream goes at end of block, bit-reversed:
//   block bit 127 = stream bit 0  = weight[0] bit 0
//   block bit  68 = stream bit 59 = weight[19] bit 2
// Bit-by-bit assembly avoids tricky 60-bit reversal arithmetic.
//-----------------------------------------------------------------------------
uint4 astc_pack_block_q8_20(uint block_mode, uint endpoints[6], uint weights[20])
{
    uint header = block_mode
                | (0u << 11u)
                | ((uint)(ASTC_CEM_LDR_RGB_DIRECT) << 13u);

    uint ep_lo = endpoints[0]
               | (endpoints[1] << 8u)
               | (endpoints[2] << 16u)
               | (endpoints[3] << 24u);
    uint ep_hi = endpoints[4]
               | (endpoints[5] << 8u);

    uint4 block;
    block.x = header | (ep_lo << 17u);
    block.y = (ep_lo >> 15u) | (ep_hi << 17u);

    uint bz_high16 = 0u;  // block.z bits 16-31 = block bits 80-95
    uint bz_mid    = 0u;  // block.z bits 4-15  = block bits 68-79  (12 bits used here)
    uint bw = 0u;         // block.w bits 0-31  = block bits 96-127
    [unroll]
    for (int i = 0; i < 20; i++) {
        uint w = weights[i] & 7u;
        [unroll] for (int b = 0; b < 3; b++) {
            uint w_bit = (w >> (uint)b) & 1u;
            uint stream_pos = (uint)i * 3u + (uint)b;        // 0..59
            uint block_pos  = 127u - stream_pos;             // 68..127
            if (block_pos >= 96u) {
                bw |= w_bit << (block_pos - 96u);
            } else if (block_pos >= 80u) {
                bz_high16 |= w_bit << (block_pos - 80u);
            } else {
                // 68..79 → block.z bits 4..15
                bz_mid |= w_bit << (block_pos - 68u + 4u);
            }
        }
    }

    block.z = (ep_hi >> 15u) | bz_mid | (bz_high16 << 16u);
    block.w = bw;
    return block;
}

#endif // ASTC_COMMON_HLSL
