// astc_encode_grid5x5.hlsl
// PoC: ASTC encoder using a 5x5 weight grid (vs default 4x4 grid).
// Currently specialized for 6x6 block size (36 texels). Decimation table
// maps the 25 grid points back to the 36 texels via bilinear sampling.
//
// Bit budget for 6x6 block:
//   header        17 bits  (block mode + CEM)
//   endpoints Q256 48 bits  (6 bytes * 8 bits)
//   gap            4 bits
//   weights Q5     59 bits  (25 weights via quint encoding)
//                 ----
//                128 bits  ✓
//
// Block mode 242:
//   row 0 layout: D H | B B | A A | R0 0 0 R2 R1
//   W = B+4 = 5, H = A+2 = 5    -> 5x5 weight grid
//   weight quant R = 5 (binary 101) -> QUANT_5 (5 levels)
//   H_precision = 0, dual_plane = 0

#ifndef ASTC_ENCODE_GRID5X5_HLSL
#define ASTC_ENCODE_GRID5X5_HLSL

#include "astc_common.hlsl"

// Quant level constants (mirror those in astc_encode_core.hlsl).
#define G5_QUANT_2   0
#define G5_QUANT_3   1
#define G5_QUANT_4   2
#define G5_QUANT_5   3
#define G5_QUANT_6   4
#define G5_QUANT_8   5
#define G5_QUANT_10  6
#define G5_QUANT_12  7
#define G5_QUANT_16  8
#define G5_QUANT_20  9
#define G5_QUANT_24  10
#define G5_QUANT_32  11
#define G5_QUANT_40  12
#define G5_QUANT_48  13
#define G5_QUANT_64  14
#define G5_QUANT_80  15
#define G5_QUANT_96  16
#define G5_QUANT_128 17
#define G5_QUANT_160 18
#define G5_QUANT_192 19
#define G5_QUANT_256 20
#define G5_QUANT_MAX 21

#include "astc_tables.hlsl"
// astc_ise.hlsl uses QUANT_MAX from astc_encode_core; provide it locally if not defined.
#ifndef QUANT_MAX
#define QUANT_2   G5_QUANT_2
#define QUANT_3   G5_QUANT_3
#define QUANT_4   G5_QUANT_4
#define QUANT_5   G5_QUANT_5
#define QUANT_6   G5_QUANT_6
#define QUANT_8   G5_QUANT_8
#define QUANT_10  G5_QUANT_10
#define QUANT_12  G5_QUANT_12
#define QUANT_16  G5_QUANT_16
#define QUANT_20  G5_QUANT_20
#define QUANT_24  G5_QUANT_24
#define QUANT_32  G5_QUANT_32
#define QUANT_40  G5_QUANT_40
#define QUANT_48  G5_QUANT_48
#define QUANT_64  G5_QUANT_64
#define QUANT_80  G5_QUANT_80
#define QUANT_96  G5_QUANT_96
#define QUANT_128 G5_QUANT_128
#define QUANT_160 G5_QUANT_160
#define QUANT_192 G5_QUANT_192
#define QUANT_256 G5_QUANT_256
#define QUANT_MAX G5_QUANT_MAX
#endif
#include "astc_ise.hlsl"

#define G5_CEM_LDR_RGB_DIRECT  8
#define G5_CEM_LDR_RGBA_DIRECT 12
#define G5_SMALL_VAL 0.00001f

// 5x5 grid in 6x6 block — decimation table.
// For each of 25 grid points (gx, gy) at block-texel position
// (gx * 5/4, gy * 5/4), sample 4 neighbors via bilinear weights.
static const uint4 g5_idx_5x5_in_6x6[25] = {
    // gy = 0 (ty = 0, ty_frac = 0)
    uint4( 0,  1,  6,  7), uint4( 1,  2,  7,  8), uint4( 2,  3,  8,  9), uint4( 3,  4,  9, 10), uint4( 5,  5, 11, 11),
    // gy = 1 (ty = 1.25, ty_frac = 0.25)
    uint4( 6,  7, 12, 13), uint4( 7,  8, 13, 14), uint4( 8,  9, 14, 15), uint4( 9, 10, 15, 16), uint4(11, 11, 17, 17),
    // gy = 2 (ty = 2.5, ty_frac = 0.5)
    uint4(12, 13, 18, 19), uint4(13, 14, 19, 20), uint4(14, 15, 20, 21), uint4(15, 16, 21, 22), uint4(17, 17, 23, 23),
    // gy = 3 (ty = 3.75, ty_frac = 0.75)
    uint4(18, 19, 24, 25), uint4(19, 20, 25, 26), uint4(20, 21, 26, 27), uint4(21, 22, 27, 28), uint4(23, 23, 29, 29),
    // gy = 4 (ty = 5, ty_frac = 0)
    uint4(30, 31, 30, 31), uint4(31, 32, 31, 32), uint4(32, 33, 32, 33), uint4(33, 34, 33, 34), uint4(35, 35, 35, 35)
};

static const float4 g5_wt_5x5_in_6x6[25] = {
    // gy = 0
    float4(1.0f,    0.0f,    0.0f,    0.0f   ),
    float4(0.75f,   0.25f,   0.0f,    0.0f   ),
    float4(0.5f,    0.5f,    0.0f,    0.0f   ),
    float4(0.25f,   0.75f,   0.0f,    0.0f   ),
    float4(1.0f,    0.0f,    0.0f,    0.0f   ),
    // gy = 1
    float4(0.75f,   0.0f,    0.25f,   0.0f   ),
    float4(0.5625f, 0.1875f, 0.1875f, 0.0625f),
    float4(0.375f,  0.375f,  0.125f,  0.125f ),
    float4(0.1875f, 0.5625f, 0.0625f, 0.1875f),
    float4(0.75f,   0.0f,    0.25f,   0.0f   ),
    // gy = 2
    float4(0.5f,    0.0f,    0.5f,    0.0f   ),
    float4(0.375f,  0.125f,  0.375f,  0.125f ),
    float4(0.25f,   0.25f,   0.25f,   0.25f  ),
    float4(0.125f,  0.375f,  0.125f,  0.375f ),
    float4(0.5f,    0.0f,    0.5f,    0.0f   ),
    // gy = 3
    float4(0.25f,   0.0f,    0.75f,   0.0f   ),
    float4(0.1875f, 0.0625f, 0.5625f, 0.1875f),
    float4(0.125f,  0.125f,  0.375f,  0.375f ),
    float4(0.0625f, 0.1875f, 0.1875f, 0.5625f),
    float4(0.25f,   0.0f,    0.75f,   0.0f   ),
    // gy = 4
    float4(1.0f,    0.0f,    0.0f,    0.0f   ),
    float4(0.75f,   0.25f,   0.0f,    0.0f   ),
    float4(0.5f,    0.5f,    0.0f,    0.0f   ),
    float4(0.25f,   0.75f,   0.0f,    0.0f   ),
    float4(1.0f,    0.0f,    0.0f,    0.0f   )
};

float4 g5_eigen(float4x4 m)
{
    float4 v = float4(0.26726f, 0.80178f, 0.53452f, 0.0f);
    [unroll] for (int i = 0; i < 8; ++i) {
        v = mul(m, v);
        float l = length(v);
        if (l < G5_SMALL_VAL) return v;
        v = v / l;
        v = mul(m, v);
        l = length(v);
        if (l < G5_SMALL_VAL) return v;
        v = v / l;
    }
    return v;
}

// PCA on 36 texels — endpoints are min/max projections clamped to [0,255].
void g5_pca_36(float4 texels[36], out float4 ep0, out float4 ep1)
{
    int i = 0;
    float4 mean = float4(0,0,0,0);
    [unroll] for (i = 0; i < 36; ++i) mean += texels[i];
    mean /= 36.0f;

    float4x4 cov = (float4x4)0;
    [unroll] for (int k = 0; k < 36; ++k) {
        float4 d = texels[k] - mean;
        [unroll] for (int a = 0; a < 4; ++a) {
            [unroll] for (int b = 0; b < 4; ++b) {
                cov[a][b] += d[a] * d[b];
            }
        }
    }
    cov /= 35.0f;

    float4 axis = g5_eigen(cov);

    float lo = 1e31f, hi = -1e31f;
    [unroll] for (i = 0; i < 36; ++i) {
        float t = dot(texels[i] - mean, axis);
        lo = min(lo, t);
        hi = max(hi, t);
    }

    ep0 = clamp(axis * lo + mean, 0.0f, 255.0f);
    ep1 = clamp(axis * hi + mean, 0.0f, 255.0f);

    // Order so darker endpoint comes first.
    float4 e0u = round(ep0);
    float4 e1u = round(ep1);
    if (e0u.x + e0u.y + e0u.z > e1u.x + e1u.y + e1u.z) {
        float4 tmp = ep0; ep0 = ep1; ep1 = tmp;
    }

    // Force alpha = 255 (CEM 8 RGB-only).
    ep0.a = 255.0f;
    ep1.a = 255.0f;
}

// Compute 25 grid weights via decimation:
//   1. For each grid point, bilinear-sample 4 nearest texels at the grid's
//      continuous block-position (grid (gx,gy) → texel (gx*5/4, gy*5/4)).
//   2. Project the sampled value onto the (ep1-ep0) axis.
//   3. Renormalize across the 25 grid samples to [0,1].
//
// We tried two alternatives that didn't improve quality:
//   - LSQ inverse with diag(B^T B)^-1 B^T pixel_proj (-0.18 dB): the grid-
//     smoothed weights span less than [0,1], even with endpoint stretching;
//     in practice the diagonal preconditioning loses information vs the
//     sample-based "grid-position view" which preserves locality.
//   - LSQ + endpoint stretch (lerp(ep0,ep1, gmin..gmax)): -0.24 dB, same
//     reason — the saturate after stretch + 0..255 clamp distorts geometry.
void g5_calc_grid_weights_25(float4 texels[36], float4 ep0, float4 ep1,
                              out float projw[25])
{
    int i = 0;
    float4 vec_k = ep1 - ep0;
    float lensq = dot(vec_k, vec_k);
    if (lensq < G5_SMALL_VAL) {
        [unroll] for (i = 0; i < 25; ++i) projw[i] = 0.0f;
        return;
    }
    vec_k = normalize(vec_k);

    float minw = 1e31f;
    float maxw = -1e31f;
    [unroll] for (i = 0; i < 25; ++i) {
        uint4  ix = g5_idx_5x5_in_6x6[i];
        float4 wt = g5_wt_5x5_in_6x6[i];
        float4 sample = texels[ix.x] * wt.x
                      + texels[ix.y] * wt.y
                      + texels[ix.z] * wt.z
                      + texels[ix.w] * wt.w;
        float w = dot(vec_k, sample - ep0);
        minw = min(minw, w);
        maxw = max(maxw, w);
        projw[i] = w;
    }

    float invlen = 1.0f / max(G5_SMALL_VAL, maxw - minw);
    [unroll] for (i = 0; i < 25; ++i) {
        projw[i] = (projw[i] - minw) * invlen;
    }
}

// ISE encode 25 weights at QUANT_5 (quint encoding, 0 extra bits per value).
// 9 quint groups × 7 bits = 63 bits theoretically; spec formula = 59 bits.
// We just call encode_quints for groups of 3; the bit count comes out right.
void g5_bise_weights_25_q5(uint nums[25], inout uint4 outputs)
{
    uint bitpos = 0;
    encode_quints(0, nums[ 0], nums[ 1], nums[ 2], outputs, bitpos);
    encode_quints(0, nums[ 3], nums[ 4], nums[ 5], outputs, bitpos);
    encode_quints(0, nums[ 6], nums[ 7], nums[ 8], outputs, bitpos);
    encode_quints(0, nums[ 9], nums[10], nums[11], outputs, bitpos);
    encode_quints(0, nums[12], nums[13], nums[14], outputs, bitpos);
    encode_quints(0, nums[15], nums[16], nums[17], outputs, bitpos);
    encode_quints(0, nums[18], nums[19], nums[20], outputs, bitpos);
    encode_quints(0, nums[21], nums[22], nums[23], outputs, bitpos);
    // Last group: 1 actual + 2 zero padding.
    encode_quints(0, nums[24], 0, 0, outputs, bitpos);
}

// Top-level encoder: 36 texels (6x6 block) → 128-bit ASTC block (5x5 grid + Q5 weights + Q256 endpoints).
uint4 encode_block_5x5_in_6x6(float4 texels[36])
{
    int i = 0;

    float4 ep0, ep1;
    g5_pca_36(texels, ep0, ep1);

    // --- Endpoints: 6 bytes at QUANT_256 (one per channel × 2 endpoints, RGB only) ---
    uint ep_quantized[8];
    uint4 e0q = (uint4)round(ep0);
    uint4 e1q = (uint4)round(ep1);
    ep_quantized[0] = e0q.r;
    ep_quantized[1] = e1q.r;
    ep_quantized[2] = e0q.g;
    ep_quantized[3] = e1q.g;
    ep_quantized[4] = e0q.b;
    ep_quantized[5] = e1q.b;
    ep_quantized[6] = 0;
    ep_quantized[7] = 0;

    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(ep_quantized, G5_QUANT_256, ep_ise);

    // --- Weights: 25 grid weights @ QUANT_5 (5 levels) ---
    float projw[25];
    g5_calc_grid_weights_25(texels, ep0, ep1, projw);

    uint wt_quantized[25];
    uint weight_range = 5; // 5 levels => quantized values 0..4
    [unroll] for (i = 0; i < 25; ++i) {
        uint q = (uint)(projw[i] * (float)(weight_range - 1) + 0.5f);
        q = clamp(q, 0u, weight_range - 1u);
        // Scramble (QUANT_5 has identity scramble for indices 0..4).
        wt_quantized[i] = scramble_table[G5_QUANT_5 * WEIGHT_QUANTIZE_NUM + q];
    }

    uint4 wt_ise = uint4(0,0,0,0);
    g5_bise_weights_25_q5(wt_quantized, wt_ise);

    // --- Block mode: row 0, A=3, B=1, R=5 (QUANT_5), H=0, D=0 → 242 ---
    const uint blockmode = 242u;

    // --- Assemble 128-bit block ---
    // ASTC stores weights from the high end with bits reversed, endpoints
    // from the low end with header. For 59 weight bits + 48 endpoint bits +
    // 17 header bits there is a 4-bit gap (block bits 65..68).
    uint4 phy = uint4(0,0,0,0);

    // Weights at the high end (block bytes 8..15), byte-reversed and bit-reversed within byte.
    phy.w |= reverse_byte( wt_ise.x        & 0xFF) << 24;
    phy.w |= reverse_byte((wt_ise.x >>  8) & 0xFF) << 16;
    phy.w |= reverse_byte((wt_ise.x >> 16) & 0xFF) <<  8;
    phy.w |= reverse_byte((wt_ise.x >> 24) & 0xFF);

    phy.z |= reverse_byte( wt_ise.y        & 0xFF) << 24;
    phy.z |= reverse_byte((wt_ise.y >>  8) & 0xFF) << 16;
    phy.z |= reverse_byte((wt_ise.y >> 16) & 0xFF) <<  8;
    phy.z |= reverse_byte((wt_ise.y >> 24) & 0xFF);

    phy.y |= reverse_byte( wt_ise.z        & 0xFF) << 24;
    phy.y |= reverse_byte((wt_ise.z >>  8) & 0xFF) << 16;
    phy.y |= reverse_byte((wt_ise.z >> 16) & 0xFF) <<  8;
    phy.y |= reverse_byte((wt_ise.z >> 24) & 0xFF);

    // Header: block mode (bits 0..10), CEM (bits 13..16).
    phy.x  = blockmode;
    phy.x |= (G5_CEM_LDR_RGB_DIRECT & 0xF) << 13;

    // Endpoints starting at bit 17 (single partition).
    phy.x |=  (ep_ise.x        & 0x7FFF ) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |=  (ep_ise.y        & 0x7FFF ) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);

    return phy;
}

#endif // ASTC_ENCODE_GRID5X5_HLSL
