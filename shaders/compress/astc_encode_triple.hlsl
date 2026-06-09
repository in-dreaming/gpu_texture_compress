// astc_encode_triple.hlsl (Optimized version - reduced unroll for size)
// Extends dual-mode block-mode search by adding a third 1:1-grid path.
// OPTIMIZATION: Use [loop] instead of [unroll] for non-critical paths to reduce SPV size.
//
// Mode A: 5x5 grid + QUANT_5  + QUANT_256 endpoints      (block mode 242)
// Mode B: 4x4 grid + QUANT_12 + QUANT_256 endpoints      (block mode 593)  [loop optimized]
// Mode C: BwxBh grid (1:1) + QUANT_N + QUANT_256 endpts  (block mode T1_BLOCKMODE) [loop optimized]

#ifndef BLOCK_W
#error "BLOCK_W must be defined"
#endif
#ifndef BLOCK_H
#error "BLOCK_H must be defined"
#endif
#ifndef BLOCK_SIZE
#error "BLOCK_SIZE must be defined"
#endif
#ifndef GRID_FUNC_NAME
#error "GRID_FUNC_NAME must be defined"
#endif
#ifndef T1_WEIGHT_Q_INDEX
#error "T1_WEIGHT_Q_INDEX must be defined"
#endif
#ifndef T1_WEIGHT_RANGE_M1
#error "T1_WEIGHT_RANGE_M1 must be defined"
#endif
#ifndef T1_WEIGHT_BITS
#error "T1_WEIGHT_BITS must be defined"
#endif
#ifndef T1_BLOCKMODE
#error "T1_BLOCKMODE must be defined"
#endif

#include "astc_common.hlsl"

#ifndef GT_QUANT_DEFINED
#define GT_QUANT_DEFINED
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

#define GT_CEM_LDR_RGB_DIRECT 8
#define GT_SMALL_VAL 0.00001f

static float4 gt_eigen(float4x4 m)
{
    float4 v = float4(0.26726f, 0.80178f, 0.53452f, 0.0f);
    [unroll] for (int i = 0; i < 8; ++i) {
        v = mul(m, v);
        float l = length(v);
        if (l < GT_SMALL_VAL) return v;
        v = v / l;
        v = mul(m, v);
        l = length(v);
        if (l < GT_SMALL_VAL) return v;
        v = v / l;
    }
    return v;
}

static float4 gt_sample_at(float4 texels[BLOCK_SIZE], uint gx, uint gy,
                            float scale_x, float scale_y)
{
    float tx = (float)gx * scale_x;
    float ty = (float)gy * scale_y;
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

static void gt_pca_full(float4 texels[BLOCK_SIZE], out float4 ep0, out float4 ep1)
{
    int i = 0;
    float4 mean = float4(0,0,0,0);
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) mean += texels[i];
    mean /= (float)BLOCK_SIZE;
    float4x4 cov = (float4x4)0;
    [unroll] for (int k = 0; k < BLOCK_SIZE; ++k) {
        float4 d = texels[k] - mean;
        [unroll] for (int a = 0; a < 4; ++a) {
            [unroll] for (int b = 0; b < 4; ++b) cov[a][b] += d[a] * d[b];
        }
    }
    cov /= (float)(BLOCK_SIZE - 1);
    float4 axis = gt_eigen(cov);
    float lo = 1e31f, hi = -1e31f;
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
        float t = dot(texels[i] - mean, axis);
        lo = min(lo, t); hi = max(hi, t);
    }
    ep0 = clamp(axis * lo + mean, 0.0f, 255.0f);
    ep1 = clamp(axis * hi + mean, 0.0f, 255.0f);
    float4 e0u = round(ep0); float4 e1u = round(ep1);
    if (e0u.x + e0u.y + e0u.z > e1u.x + e1u.y + e1u.z) {
        float4 tmp = ep0; ep0 = ep1; ep1 = tmp;
    }
    ep0.a = 255.0f; ep1.a = 255.0f;
}

static void gt_pca_16(float4 samples[16], out float4 ep0, out float4 ep1)
{
    int i = 0;
    float4 mean = float4(0,0,0,0);
    [unroll] for (i = 0; i < 16; ++i) mean += samples[i];
    mean /= 16.0f;
    float4x4 cov = (float4x4)0;
    [unroll] for (int k = 0; k < 16; ++k) {
        float4 d = samples[k] - mean;
        [unroll] for (int a = 0; a < 4; ++a) {
            [unroll] for (int b = 0; b < 4; ++b) cov[a][b] += d[a] * d[b];
        }
    }
    cov /= 15.0f;
    float4 axis = gt_eigen(cov);
    float lo = 1e31f, hi = -1e31f;
    [unroll] for (i = 0; i < 16; ++i) {
        float t = dot(samples[i] - mean, axis);
        lo = min(lo, t); hi = max(hi, t);
    }
    ep0 = clamp(axis * lo + mean, 0.0f, 255.0f);
    ep1 = clamp(axis * hi + mean, 0.0f, 255.0f);
    float4 e0u = round(ep0); float4 e1u = round(ep1);
    if (e0u.x + e0u.y + e0u.z > e1u.x + e1u.y + e1u.z) {
        float4 tmp = ep0; ep0 = ep1; ep1 = tmp;
    }
    ep0.a = 255.0f; ep1.a = 255.0f;
}

// ===== Mode A: 5x5 grid + Q5 (keep unroll - primary path) =====

static void gt_calc_5x5_levels(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1, out uint levels[25])
{
    int i = 0;
    float4 vec_k = ep1 - ep0;
    if (dot(vec_k, vec_k) < GT_SMALL_VAL) {
        [unroll] for (i = 0; i < 25; ++i) levels[i] = 0u;
        return;
    }
    vec_k = normalize(vec_k);
    float scale_x = (float)(BLOCK_W - 1) * 0.25f;
    float scale_y = (float)(BLOCK_H - 1) * 0.25f;
    float projw[25];
    float minw = 1e31f, maxw = -1e31f;
    [unroll] for (uint gy = 0; gy < 5; ++gy) {
        [unroll] for (uint gx = 0; gx < 5; ++gx) {
            float4 sample = gt_sample_at(texels, gx, gy, scale_x, scale_y);
            float w = dot(vec_k, sample - ep0);
            uint idx = gy * 5u + gx;
            minw = min(minw, w); maxw = max(maxw, w);
            projw[idx] = w;
        }
    }
    float invlen = 1.0f / max(GT_SMALL_VAL, maxw - minw);
    [unroll] for (i = 0; i < 25; ++i) {
        float n = saturate((projw[i] - minw) * invlen);
        levels[i] = clamp((uint)(n * 4.0f + 0.5f), 0u, 4u);
    }
}

static float gt_recon_error_5x5(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1, uint levels[25])
{
    float dw[25];
    [unroll] for (uint i = 0; i < 25; ++i) dw[i] = (float)levels[i] / 4.0f;
    uint Bw = (uint)BLOCK_W; uint Bh = (uint)BLOCK_H;
    uint Ds = (1024u + (Bw - 1u) / 2u) / (Bw - 1u);
    uint Dt = (1024u + (Bh - 1u) / 2u) / (Bh - 1u);
    float total = 0.0f;
    [unroll] for (uint p = 0; p < BLOCK_SIZE; ++p) {
        uint s = p % Bw; uint t = p / Bw;
        uint gs = (s * Ds * 4u + 32u) >> 6;
        uint gt2 = (t * Dt * 4u + 32u) >> 6;
        uint js = gs >> 4; uint jt = gt2 >> 4;
        uint fs = gs & 15u; uint ft = gt2 & 15u;
        uint js1 = min(js + 1u, 4u); uint jt1 = min(jt + 1u, 4u);
        uint w11 = (fs * ft + 8u) >> 4;
        uint w10 = ft - w11; uint w01 = fs - w11;
        uint w00 = 16u - fs - ft + w11;
        float weight = ((float)w00 * dw[jt*5u+js] + (float)w01 * dw[jt*5u+js1]
                      + (float)w10 * dw[jt1*5u+js] + (float)w11 * dw[jt1*5u+js1]) / 16.0f;
        float4 recon = lerp(ep0, ep1, weight);
        float4 d = recon - texels[p];
        total += dot(d, d);
    }
    return total;
}

static void gt_bise_25_q5(uint scrambled[25], inout uint4 outputs)
{
    uint bp = 0;
    encode_quints(0, scrambled[ 0], scrambled[ 1], scrambled[ 2], outputs, bp);
    encode_quints(0, scrambled[ 3], scrambled[ 4], scrambled[ 5], outputs, bp);
    encode_quints(0, scrambled[ 6], scrambled[ 7], scrambled[ 8], outputs, bp);
    encode_quints(0, scrambled[ 9], scrambled[10], scrambled[11], outputs, bp);
    encode_quints(0, scrambled[12], scrambled[13], scrambled[14], outputs, bp);
    encode_quints(0, scrambled[15], scrambled[16], scrambled[17], outputs, bp);
    encode_quints(0, scrambled[18], scrambled[19], scrambled[20], outputs, bp);
    encode_quints(0, scrambled[21], scrambled[22], scrambled[23], outputs, bp);
    encode_quints(0, scrambled[24], 0, 0, outputs, bp);
}

static uint4 gt_pack_5x5_q5(float4 ep0, float4 ep1, uint levels[25])
{
    uint epq[8];
    uint4 e0q = (uint4)round(ep0); uint4 e1q = (uint4)round(ep1);
    epq[0]=e0q.r; epq[1]=e1q.r; epq[2]=e0q.g; epq[3]=e1q.g;
    epq[4]=e0q.b; epq[5]=e1q.b; epq[6]=0; epq[7]=0;
    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(epq, QUANT_256, ep_ise);
    uint sc[25];
    [unroll] for (uint i = 0; i < 25; ++i) sc[i] = scramble_table[QUANT_5 * WEIGHT_QUANTIZE_NUM + levels[i]];
    uint4 wt = uint4(0,0,0,0);
    gt_bise_25_q5(sc, wt);

    uint4 phy = uint4(0,0,0,0);
    phy.w |= reverse_byte(wt.x & 0xFF) << 24;
    phy.w |= reverse_byte((wt.x >> 8) & 0xFF) << 16;
    phy.w |= reverse_byte((wt.x >> 16) & 0xFF) << 8;
    phy.w |= reverse_byte((wt.x >> 24) & 0xFF);
    phy.z |= reverse_byte(wt.y & 0xFF) << 24;
    phy.z |= reverse_byte((wt.y >> 8) & 0xFF) << 16;
    phy.z |= reverse_byte((wt.y >> 16) & 0xFF) << 8;
    phy.z |= reverse_byte((wt.y >> 24) & 0xFF);
    phy.y |= reverse_byte(wt.z & 0xFF) << 24;
    phy.y |= reverse_byte((wt.z >> 8) & 0xFF) << 16;
    phy.y |= reverse_byte((wt.z >> 16) & 0xFF) << 8;
    phy.y |= reverse_byte((wt.z >> 24) & 0xFF);
    phy.x = 242u;
    phy.x |= (GT_CEM_LDR_RGB_DIRECT & 0xF) << 13;
    phy.x |= (ep_ise.x & 0x7FFF) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |= (ep_ise.y & 0x7FFF) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);
    return phy;
}

// ===== Mode B: 4x4 grid + Q12 (use [loop] for size reduction) =====

static void gt_calc_4x4_levels(float4 samples[16], float4 ep0, float4 ep1, out uint levels[16])
{
    int i = 0;
    float4 vec_k = ep1 - ep0;
    if (dot(vec_k, vec_k) < GT_SMALL_VAL) {
        [loop] for (i = 0; i < 16; ++i) levels[i] = 0u;  // Changed: [unroll] -> [loop]
        return;
    }
    vec_k = normalize(vec_k);
    float projw[16];
    float minw = 1e31f, maxw = -1e31f;
    [loop] for (i = 0; i < 16; ++i) {  // Changed: [unroll] -> [loop]
        float w = dot(vec_k, samples[i] - ep0);
        minw = min(minw, w); maxw = max(maxw, w);
        projw[i] = w;
    }
    float invlen = 1.0f / max(GT_SMALL_VAL, maxw - minw);
    [loop] for (i = 0; i < 16; ++i) {  // Changed: [unroll] -> [loop]
        float n = saturate((projw[i] - minw) * invlen);
        levels[i] = clamp((uint)(n * 11.0f + 0.5f), 0u, 11u);
    }
}

static float gt_recon_error_4x4(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1, uint levels[16])
{
    float dw[16];
    [loop] for (uint i = 0; i < 16; ++i) dw[i] = (float)levels[i] / 11.0f;  // Changed: [unroll] -> [loop]
    uint Bw = (uint)BLOCK_W; uint Bh = (uint)BLOCK_H;
    uint Ds = (1024u + (Bw - 1u) / 2u) / (Bw - 1u);
    uint Dt = (1024u + (Bh - 1u) / 2u) / (Bh - 1u);
    float total = 0.0f;
    [loop] for (uint p = 0; p < BLOCK_SIZE; ++p) {  // Changed: [unroll] -> [loop]
        uint s = p % Bw; uint t = p / Bw;
        uint gs = (s * Ds * 3u + 32u) >> 6;
        uint gt2 = (t * Dt * 3u + 32u) >> 6;
        uint js = gs >> 4; uint jt = gt2 >> 4;
        uint fs = gs & 15u; uint ft = gt2 & 15u;
        uint js1 = min(js + 1u, 3u); uint jt1 = min(jt + 1u, 3u);
        uint w11 = (fs * ft + 8u) >> 4;
        uint w10 = ft - w11; uint w01 = fs - w11;
        uint w00 = 16u - fs - ft + w11;
        float weight = ((float)w00 * dw[jt*4u+js] + (float)w01 * dw[jt*4u+js1]
                      + (float)w10 * dw[jt1*4u+js] + (float)w11 * dw[jt1*4u+js1]) / 16.0f;
        float4 recon = lerp(ep0, ep1, weight);
        float4 d = recon - texels[p];
        total += dot(d, d);
    }
    return total;
}

static void gt_bise_16_q12(uint scrambled[16], inout uint4 outputs)
{
    uint bp = 0;
    encode_trits(2, scrambled[ 0], scrambled[ 1], scrambled[ 2], scrambled[ 3], scrambled[ 4], outputs, bp);
    encode_trits(2, scrambled[ 5], scrambled[ 6], scrambled[ 7], scrambled[ 8], scrambled[ 9], outputs, bp);
    encode_trits(2, scrambled[10], scrambled[11], scrambled[12], scrambled[13], scrambled[14], outputs, bp);
    encode_trits(2, scrambled[15], 0, 0, 0, 0, outputs, bp);
}

static uint4 gt_pack_4x4_q12(float4 ep0, float4 ep1, uint levels[16])
{
    uint epq[8];
    uint4 e0q = (uint4)round(ep0); uint4 e1q = (uint4)round(ep1);
    epq[0]=e0q.r; epq[1]=e1q.r; epq[2]=e0q.g; epq[3]=e1q.g;
    epq[4]=e0q.b; epq[5]=e1q.b; epq[6]=0; epq[7]=0;
    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(epq, QUANT_256, ep_ise);
    uint sc[16];
    [loop] for (uint i = 0; i < 16; ++i) sc[i] = scramble_table[QUANT_12 * WEIGHT_QUANTIZE_NUM + levels[i]];  // Changed: [unroll] -> [loop]
    uint4 wt = uint4(0,0,0,0);
    gt_bise_16_q12(sc, wt);

    uint4 phy = uint4(0,0,0,0);
    phy.w |= reverse_byte(wt.x & 0xFF) << 24;
    phy.w |= reverse_byte((wt.x >> 8) & 0xFF) << 16;
    phy.w |= reverse_byte((wt.x >> 16) & 0xFF) << 8;
    phy.w |= reverse_byte((wt.x >> 24) & 0xFF);
    phy.z |= reverse_byte(wt.y & 0xFF) << 24;
    phy.z |= reverse_byte((wt.y >> 8) & 0xFF) << 16;
    phy.z |= reverse_byte((wt.y >> 16) & 0xFF) << 8;
    phy.z |= reverse_byte((wt.y >> 24) & 0xFF);
    phy.y |= reverse_byte(wt.z & 0xFF) << 24;
    phy.y |= reverse_byte((wt.z >> 8) & 0xFF) << 16;
    phy.y |= reverse_byte((wt.z >> 16) & 0xFF) << 8;
    phy.y |= reverse_byte((wt.z >> 24) & 0xFF);
    phy.x = 593u;
    phy.x |= (GT_CEM_LDR_RGB_DIRECT & 0xF) << 13;
    phy.x |= (ep_ise.x & 0x7FFF) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |= (ep_ise.y & 0x7FFF) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);
    return phy;
}

// ===== Mode C: 1:1 grid (BwxBh) + QN (use [loop] for size reduction) =====

static void gt_calc_1to1_levels(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1, out uint levels[BLOCK_SIZE])
{
    int i = 0;
    float4 vec_k = ep1 - ep0;
    if (dot(vec_k, vec_k) < GT_SMALL_VAL) {
        [loop] for (i = 0; i < BLOCK_SIZE; ++i) levels[i] = 0u;  // Changed: [unroll] -> [loop]
        return;
    }
    vec_k = normalize(vec_k);
    float projw[BLOCK_SIZE];
    float minw = 1e31f, maxw = -1e31f;
    [loop] for (i = 0; i < BLOCK_SIZE; ++i) {  // Changed: [unroll] -> [loop]
        float w = dot(vec_k, texels[i] - ep0);
        minw = min(minw, w); maxw = max(maxw, w);
        projw[i] = w;
    }
    float invlen = 1.0f / max(GT_SMALL_VAL, maxw - minw);
    [loop] for (i = 0; i < BLOCK_SIZE; ++i) {  // Changed: [unroll] -> [loop]
        float n = saturate((projw[i] - minw) * invlen);
        levels[i] = clamp((uint)(n * (float)T1_WEIGHT_RANGE_M1 + 0.5f), 0u, (uint)T1_WEIGHT_RANGE_M1);
    }
}

// 1:1 reconstruction error: trivial (pixel weight = grid weight at that pixel).
static float gt_recon_error_1to1(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1, uint levels[BLOCK_SIZE])
{
    float total = 0.0f;
    [loop] for (uint i = 0; i < BLOCK_SIZE; ++i) {  // Changed: [unroll] -> [loop]
        float w = (float)levels[i] / (float)T1_WEIGHT_RANGE_M1;
        float4 recon = lerp(ep0, ep1, w);
        float4 d = recon - texels[i];
        total += dot(d, d);
    }
    return total;
}

static uint4 gt_pack_1to1(float4 ep0, float4 ep1, uint levels[BLOCK_SIZE])
{
    uint epq[8];
    uint4 e0q = (uint4)round(ep0); uint4 e1q = (uint4)round(ep1);
    epq[0]=e0q.r; epq[1]=e1q.r; epq[2]=e0q.g; epq[3]=e1q.g;
    epq[4]=e0q.b; epq[5]=e1q.b; epq[6]=0; epq[7]=0;
    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(epq, QUANT_256, ep_ise);

    uint sc[BLOCK_SIZE];
    [loop] for (uint i = 0; i < BLOCK_SIZE; ++i) {  // Changed: [unroll] -> [loop]
        sc[i] = scramble_table[T1_WEIGHT_Q_INDEX * WEIGHT_QUANTIZE_NUM + levels[i]];
    }

    uint4 wt = uint4(0,0,0,0);
    uint bp = 0;
    [loop] for (uint i = 0; i < BLOCK_SIZE; ++i) {  // Changed: [unroll] -> [loop]
        orbits8_ptr(wt, bp, sc[i], (uint)T1_WEIGHT_BITS);
    }

    uint4 phy = uint4(0,0,0,0);
    phy.w |= reverse_byte(wt.x & 0xFF) << 24;
    phy.w |= reverse_byte((wt.x >> 8) & 0xFF) << 16;
    phy.w |= reverse_byte((wt.x >> 16) & 0xFF) << 8;
    phy.w |= reverse_byte((wt.x >> 24) & 0xFF);
    phy.z |= reverse_byte(wt.y & 0xFF) << 24;
    phy.z |= reverse_byte((wt.y >> 8) & 0xFF) << 16;
    phy.z |= reverse_byte((wt.y >> 16) & 0xFF) << 8;
    phy.z |= reverse_byte((wt.y >> 24) & 0xFF);
    phy.y |= reverse_byte(wt.z & 0xFF) << 24;
    phy.y |= reverse_byte((wt.z >> 8) & 0xFF) << 16;
    phy.y |= reverse_byte((wt.z >> 16) & 0xFF) << 8;
    phy.y |= reverse_byte((wt.z >> 24) & 0xFF);
    phy.x = (uint)T1_BLOCKMODE;
    phy.x |= (GT_CEM_LDR_RGB_DIRECT & 0xF) << 13;
    phy.x |= (ep_ise.x & 0x7FFF) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |= (ep_ise.y & 0x7FFF) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);
    return phy;
}

// ===== Top-level: QualityLevel-adaptive block-mode search =====
// QualityLevel 0: Mode A only (fastest, smallest code)
// QualityLevel 1: Mode A + B (balanced)
// QualityLevel 2: All three modes (best quality)

uint4 GRID_FUNC_NAME(float4 texels[BLOCK_SIZE])
{
    // Mode A: 5x5 grid + Q5 (always computed)
    float4 ep5_0, ep5_1;
    gt_pca_full(texels, ep5_0, ep5_1);
    uint lev5[25];
    gt_calc_5x5_levels(texels, ep5_0, ep5_1, lev5);
    float err5 = gt_recon_error_5x5(texels, ep5_0, ep5_1, lev5);

#if QUALITY_LEVEL >= 1
    // Mode B: 4x4 grid + Q12 (subsampled to 16)
    float4 sm16[16];
    float sx4 = (float)(BLOCK_W - 1) / 3.0f;
    float sy4 = (float)(BLOCK_H - 1) / 3.0f;
    [unroll] for (uint gy = 0; gy < 4; ++gy) {
        [unroll] for (uint gx = 0; gx < 4; ++gx) {
            sm16[gy * 4 + gx] = gt_sample_at(texels, gx, gy, sx4, sy4);
        }
    }
    float4 ep4_0, ep4_1;
    gt_pca_16(sm16, ep4_0, ep4_1);
    uint lev4[16];
    gt_calc_4x4_levels(sm16, ep4_0, ep4_1, lev4);
    float err4 = gt_recon_error_4x4(texels, ep4_0, ep4_1, lev4);
#endif

#if QUALITY_LEVEL >= 2
    // Mode C: 1:1 grid + QN
    float4 ep1_0 = ep5_0;  // PCA on full block already done; reuse
    float4 ep1_1 = ep5_1;
    uint lev1[BLOCK_SIZE];
    gt_calc_1to1_levels(texels, ep1_0, ep1_1, lev1);
    float err1 = gt_recon_error_1to1(texels, ep1_0, ep1_1, lev1);
#endif

    // Pick best mode based on QualityLevel
#if QUALITY_LEVEL == 0
    // Fast: Mode A only
    return gt_pack_5x5_q5(ep5_0, ep5_1, lev5);
#elif QUALITY_LEVEL == 1
    // Balanced: Mode A vs B
    if (err5 <= err4) {
        return gt_pack_5x5_q5(ep5_0, ep5_1, lev5);
    } else {
        return gt_pack_4x4_q12(ep4_0, ep4_1, lev4);
    }
#else
    // Best: All three modes
    if (err5 <= err4 && err5 <= err1) {
        return gt_pack_5x5_q5(ep5_0, ep5_1, lev5);
    } else if (err4 <= err1) {
        return gt_pack_4x4_q12(ep4_0, ep4_1, lev4);
    } else {
        return gt_pack_1to1(ep1_0, ep1_1, lev1);
    }
#endif
}
