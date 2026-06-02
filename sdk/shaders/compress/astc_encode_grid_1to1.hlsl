// astc_encode_grid_1to1.hlsl
// 1:1 weight grid encoder where grid size matches block size exactly
// (so the decoder doesn't bilinearly smooth, and the encoder sees every pixel).
//
// This is the same pattern that makes ASTC 4x4 (4x4 grid + Q12) reach 47.79 dB
// and ASTC 5x5 (5x5 grid + Q5) reach 41.89 dB. Generalize it to other small
// block sizes that fit a Q-level into the bit budget:
//
//   block | weights | bits/weight | weight bits | endpoints | header | total | OK?
//   5x4   |   20    |   3 (Q8)    |     60      |    48     |   17   |  125  |  ✓
//   6x5   |   30    |   2 (Q4)    |     60      |    48     |   17   |  125  |  ✓
//   6x6   |   36    |  ~1.585(Q3) |     58      |    48     |   17   |  123  |  ✓
//   8x5   |   40    |   2 (Q4)    |     80 ✗    |     -     |   -    |   -   |  ✗
//
// Required macros (set before #include):
//   BLOCK_W, BLOCK_H, BLOCK_SIZE
//   WEIGHT_Q_INDEX                  - the QUANT_N index (e.g. QUANT_8 = 5)
//   WEIGHT_RANGE_M1                 - levels - 1 (e.g. 7 for Q8, 3 for Q4)
//   WEIGHT_BITS                     - bits per weight at this Q (e.g. 3 for Q8, 2 for Q4)
//   ONETOONE_FUNC_NAME              - top-level encoder function name
//   ONETOONE_BLOCKMODE              - precomputed block mode value for this combo
//
// Block mode formula (row 0): A = BLOCK_H - 2, B = BLOCK_W - 4, R from QUANT, H = (Q >= QUANT_8) ? 1 : 0
//   5x4 + Q8 : A=2, B=1, R=7 (h=0)  → 211
//   6x5 + Q4 : A=3, B=2, R=4 (h=0)  → 354
//
// (Q3 needs trit ISE, not direct bit pack — handled in a separate variant.)

#ifndef BLOCK_W
#error "BLOCK_W must be defined"
#endif
#ifndef BLOCK_H
#error "BLOCK_H must be defined"
#endif
#ifndef BLOCK_SIZE
#error "BLOCK_SIZE must be defined"
#endif
#ifndef WEIGHT_Q_INDEX
#error "WEIGHT_Q_INDEX must be defined"
#endif
#ifndef WEIGHT_RANGE_M1
#error "WEIGHT_RANGE_M1 must be defined"
#endif
#ifndef WEIGHT_BITS
#error "WEIGHT_BITS must be defined"
#endif
#ifndef ONETOONE_FUNC_NAME
#error "ONETOONE_FUNC_NAME must be defined"
#endif
#ifndef ONETOONE_BLOCKMODE
#error "ONETOONE_BLOCKMODE must be defined"
#endif

#include "astc_common.hlsl"

#ifndef G1_QUANT_DEFINED
#define G1_QUANT_DEFINED
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

#ifndef G1_CEM_DEFINED
#define G1_CEM_DEFINED
#define G1_CEM_LDR_RGB_DIRECT 8
#define G1_SMALL_VAL 0.00001f
#endif

static float4 g1_eigen(float4x4 m)
{
    float4 v = float4(0.26726f, 0.80178f, 0.53452f, 0.0f);
    [unroll] for (int i = 0; i < 8; ++i) {
        v = mul(m, v);
        float l = length(v);
        if (l < G1_SMALL_VAL) return v;
        v = v / l;
        v = mul(m, v);
        l = length(v);
        if (l < G1_SMALL_VAL) return v;
        v = v / l;
    }
    return v;
}

uint4 ONETOONE_FUNC_NAME(float4 texels[BLOCK_SIZE])
{
    int i = 0;

    // ===== PCA on all BLOCK_SIZE pixels =====
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

    float4 axis = g1_eigen(cov);

    float lo =  1e31f, hi = -1e31f;
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
        float t = dot(texels[i] - mean, axis);
        lo = min(lo, t); hi = max(hi, t);
    }
    float4 ep0 = clamp(axis * lo + mean, 0.0f, 255.0f);
    float4 ep1 = clamp(axis * hi + mean, 0.0f, 255.0f);
    float4 e0u = round(ep0);
    float4 e1u = round(ep1);
    if (e0u.x + e0u.y + e0u.z > e1u.x + e1u.y + e1u.z) {
        float4 tmp = ep0; ep0 = ep1; ep1 = tmp;
    }
    ep0.a = 255.0f;
    ep1.a = 255.0f;

    // ===== Per-pixel weight (1:1 grid - direct projection, no bilinear) =====
    float4 vec_k = ep1 - ep0;
    float lensq = dot(vec_k, vec_k);
    float projw[BLOCK_SIZE];
    if (lensq < G1_SMALL_VAL) {
        [unroll] for (i = 0; i < BLOCK_SIZE; ++i) projw[i] = 0.0f;
    } else {
        vec_k = normalize(vec_k);
        float minp =  1e31f, maxp = -1e31f;
        [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
            float w = dot(vec_k, texels[i] - ep0);
            minp = min(minp, w); maxp = max(maxp, w);
            projw[i] = w;
        }
        float invlen = 1.0f / max(G1_SMALL_VAL, maxp - minp);
        [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
            projw[i] = saturate((projw[i] - minp) * invlen);
        }
    }

    // ===== Quantize per-pixel weights to WEIGHT_RANGE_M1 + 1 levels =====
    uint levels[BLOCK_SIZE];
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
        uint q = (uint)(projw[i] * (float)WEIGHT_RANGE_M1 + 0.5f);
        levels[i] = clamp(q, 0u, (uint)WEIGHT_RANGE_M1);
    }

    // ===== Endpoints @ QUANT_256 =====
    uint ep_quantized[8];
    uint4 e0q = (uint4)round(ep0);
    uint4 e1q = (uint4)round(ep1);
    ep_quantized[0] = e0q.r;  ep_quantized[1] = e1q.r;
    ep_quantized[2] = e0q.g;  ep_quantized[3] = e1q.g;
    ep_quantized[4] = e0q.b;  ep_quantized[5] = e1q.b;
    ep_quantized[6] = 0;      ep_quantized[7] = 0;
    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(ep_quantized, QUANT_256, ep_ise);

    // ===== Scramble + ISE pack weights (direct bit pack at WEIGHT_BITS bits each) =====
    uint scrambled[BLOCK_SIZE];
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
        scrambled[i] = scramble_table[WEIGHT_Q_INDEX * WEIGHT_QUANTIZE_NUM + levels[i]];
    }

    uint4 wt_ise = uint4(0,0,0,0);
    uint bitpos = 0;
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
        orbits8_ptr(wt_ise, bitpos, scrambled[i], (uint)WEIGHT_BITS);
    }

    // ===== Assemble 128-bit block =====
    const uint blockmode = (uint)ONETOONE_BLOCKMODE;

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
    phy.x |= (G1_CEM_LDR_RGB_DIRECT & 0xF) << 13;
    phy.x |=  (ep_ise.x        & 0x7FFF ) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |=  (ep_ise.y        & 0x7FFF ) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);
    return phy;
}
