// astc_encode_grid5x5_generic.hlsl
// Parameterized 5x5 weight grid encoder for ANY block size >= 5x5.
// Replaces the hardcoded 6x6 decimation table with on-the-fly bilinear
// sampling, so the same code path works for 5x5, 6x5, 6x6, 8x5, 8x6,
// 8x8, etc.
//
// Required macros (set by including shader BEFORE including this file):
//   BLOCK_W, BLOCK_H     - block dimensions
//   BLOCK_SIZE           - = BLOCK_W * BLOCK_H
//   GRID_FUNC_NAME       - top-level encoder function name (avoids collisions
//                          when multiple block-size encoders coexist; e.g.
//                          encode_block_5x5_in_6x6, encode_block_5x5_in_8x8)
//
// Bit budget (any block 5x5+):
//   header        17 bits  (block mode + CEM)
//   endpoints     48 bits  (6 bytes @ QUANT_256)
//   gap            4 bits
//   weights       59 bits  (25 weights @ QUANT_5 via quints)
//                 ----
//                128 bits  ✓
//
// Block mode 242: 5x5 weight grid + QUANT_5 weights, single plane, H=0.

#ifndef BLOCK_W
#error "BLOCK_W must be defined before including astc_encode_grid5x5_generic.hlsl"
#endif
#ifndef BLOCK_H
#error "BLOCK_H must be defined before including astc_encode_grid5x5_generic.hlsl"
#endif
#ifndef BLOCK_SIZE
#error "BLOCK_SIZE must be defined before including astc_encode_grid5x5_generic.hlsl"
#endif
#ifndef GRID_FUNC_NAME
#error "GRID_FUNC_NAME must be defined before including astc_encode_grid5x5_generic.hlsl"
#endif

#include "astc_common.hlsl"

#ifndef G5G_QUANT_DEFINED
#define G5G_QUANT_DEFINED
#define QUANT_2   0
#define QUANT_3   1
#define QUANT_4   2
#define QUANT_5   3
#define QUANT_6   4
#define QUANT_8   5
#define QUANT_10  6
#define QUANT_12  7
#define QUANT_16  8
#define QUANT_20  9
#define QUANT_24  10
#define QUANT_32  11
#define QUANT_40  12
#define QUANT_48  13
#define QUANT_64  14
#define QUANT_80  15
#define QUANT_96  16
#define QUANT_128 17
#define QUANT_160 18
#define QUANT_192 19
#define QUANT_256 20
#define QUANT_MAX 21
#endif

#include "astc_tables.hlsl"
#include "astc_ise.hlsl"

#ifndef G5G_CEM_DEFINED
#define G5G_CEM_DEFINED
#define G5G_CEM_LDR_RGB_DIRECT 8
#define G5G_SMALL_VAL 0.00001f
#endif

// All helpers are static (file-scope) to avoid name collisions if this header
// is somehow included from multiple TUs in a future build (currently each
// shader is its own TU, but cheap insurance).
//
// The TOP-LEVEL encoder function uses the user-provided GRID_FUNC_NAME so the
// caller (e.g. astc_8x8.hlsl) has a distinct named entry point.

// Bilinear sample of 4 nearest texels at the 5x5 grid's continuous block
// position. Grid (gx, gy) → block-texel position (gx*(Bw-1)/4, gy*(Bh-1)/4).
static float4 g5g_sample(float4 texels[BLOCK_SIZE], uint gx, uint gy)
{
    float tx = (float)gx * (float)(BLOCK_W - 1) * 0.25f;
    float ty = (float)gy * (float)(BLOCK_H - 1) * 0.25f;

    uint tx_i = (uint)tx;
    float tx_f = tx - (float)tx_i;
    uint ty_i = (uint)ty;
    float ty_f = ty - (float)ty_i;

    uint tx_r = min(tx_i + 1u, (uint)(BLOCK_W - 1));
    uint ty_b = min(ty_i + 1u, (uint)(BLOCK_H - 1));

    float4 tl = texels[ty_i * (uint)BLOCK_W + tx_i];
    float4 tr = texels[ty_i * (uint)BLOCK_W + tx_r];
    float4 bl = texels[ty_b * (uint)BLOCK_W + tx_i];
    float4 br = texels[ty_b * (uint)BLOCK_W + tx_r];

    return tl * ((1.0f - tx_f) * (1.0f - ty_f))
         + tr * (tx_f * (1.0f - ty_f))
         + bl * ((1.0f - tx_f) * ty_f)
         + br * (tx_f * ty_f);
}

static float4 g5g_eigen(float4x4 m)
{
    float4 v = float4(0.26726f, 0.80178f, 0.53452f, 0.0f);
    [unroll] for (int i = 0; i < 8; ++i) {
        v = mul(m, v);
        float l = length(v);
        if (l < G5G_SMALL_VAL) return v;
        v = v / l;
        v = mul(m, v);
        l = length(v);
        if (l < G5G_SMALL_VAL) return v;
        v = v / l;
    }
    return v;
}

static void g5g_pca(float4 texels[BLOCK_SIZE], out float4 ep0, out float4 ep1)
{
    int i = 0;
    float4 mean = float4(0,0,0,0);
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) mean += texels[i];
    mean /= (float)BLOCK_SIZE;

    float4x4 cov = (float4x4)0;
    [unroll] for (int k = 0; k < BLOCK_SIZE; ++k) {
        float4 d = texels[k] - mean;
        [unroll] for (int a = 0; a < 4; ++a) {
            [unroll] for (int b = 0; b < 4; ++b) {
                cov[a][b] += d[a] * d[b];
            }
        }
    }
    cov /= (float)(BLOCK_SIZE - 1);

    float4 axis = g5g_eigen(cov);

    float lo =  1e31f;
    float hi = -1e31f;
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
        float t = dot(texels[i] - mean, axis);
        lo = min(lo, t);
        hi = max(hi, t);
    }

    ep0 = clamp(axis * lo + mean, 0.0f, 255.0f);
    ep1 = clamp(axis * hi + mean, 0.0f, 255.0f);

    float4 e0u = round(ep0);
    float4 e1u = round(ep1);
    if (e0u.x + e0u.y + e0u.z > e1u.x + e1u.y + e1u.z) {
        float4 tmp = ep0; ep0 = ep1; ep1 = tmp;
    }

    ep0.a = 255.0f;
    ep1.a = 255.0f;
}

// 25 grid weights via decimation: each grid point is bilinear sample of 4
// nearest texels at its continuous block position. Project onto axis,
// renormalize over the 25 grid samples to [0,1].
static void g5g_calc_weights(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1,
                              out float projw[25])
{
    int i = 0;
    float4 vec_k = ep1 - ep0;
    float lensq = dot(vec_k, vec_k);
    if (lensq < G5G_SMALL_VAL) {
        [unroll] for (i = 0; i < 25; ++i) projw[i] = 0.0f;
        return;
    }
    vec_k = normalize(vec_k);

    float minw =  1e31f;
    float maxw = -1e31f;
    [unroll] for (uint gy = 0; gy < 5; ++gy) {
        [unroll] for (uint gx = 0; gx < 5; ++gx) {
            float4 sample = g5g_sample(texels, gx, gy);
            float w = dot(vec_k, sample - ep0);
            uint idx = gy * 5u + gx;
            minw = min(minw, w);
            maxw = max(maxw, w);
            projw[idx] = w;
        }
    }

    float invlen = 1.0f / max(G5G_SMALL_VAL, maxw - minw);
    [unroll] for (i = 0; i < 25; ++i) {
        projw[i] = saturate((projw[i] - minw) * invlen);
    }
}

// ISE encode 25 weights at QUANT_5 (quint encoding, 0 extra bits per value).
static void g5g_bise_25_q5(uint nums[25], inout uint4 outputs)
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
    encode_quints(0, nums[24], 0, 0, outputs, bitpos);
}

uint4 GRID_FUNC_NAME(float4 texels[BLOCK_SIZE])
{
    int i = 0;

    float4 ep0, ep1;
    g5g_pca(texels, ep0, ep1);

    // Endpoints: 6 bytes @ QUANT_256.
    uint ep_quantized[8];
    uint4 e0q = (uint4)round(ep0);
    uint4 e1q = (uint4)round(ep1);
    ep_quantized[0] = e0q.r;  ep_quantized[1] = e1q.r;
    ep_quantized[2] = e0q.g;  ep_quantized[3] = e1q.g;
    ep_quantized[4] = e0q.b;  ep_quantized[5] = e1q.b;
    ep_quantized[6] = 0;      ep_quantized[7] = 0;

    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(ep_quantized, QUANT_256, ep_ise);

    // Weights: 25 grid weights @ QUANT_5.
    float projw[25];
    g5g_calc_weights(texels, ep0, ep1, projw);

    uint wt_quantized[25];
    uint weight_range = 5;
    [unroll] for (i = 0; i < 25; ++i) {
        uint q = (uint)(projw[i] * (float)(weight_range - 1) + 0.5f);
        q = clamp(q, 0u, weight_range - 1u);
        wt_quantized[i] = scramble_table[QUANT_5 * WEIGHT_QUANTIZE_NUM + q];
    }

    uint4 wt_ise = uint4(0,0,0,0);
    g5g_bise_25_q5(wt_quantized, wt_ise);

    // Block mode 242 (row 0: A=3, B=1, R=5 → 5x5 grid, Q5, H=0, D=0).
    const uint blockmode = 242u;

    // Assemble 128-bit block (weights at high end, byte-reversed; endpoints + header at low end).
    uint4 phy = uint4(0,0,0,0);

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

    phy.x  = blockmode;
    phy.x |= (G5G_CEM_LDR_RGB_DIRECT & 0xF) << 13;

    phy.x |=  (ep_ise.x        & 0x7FFF ) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |=  (ep_ise.y        & 0x7FFF ) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);

    return phy;
}
