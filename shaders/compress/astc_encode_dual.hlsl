// astc_encode_dual.hlsl (Optimized version - reduced unroll for size)
// Per-block block-mode search: encodes the input block twice (once with 5x5
// weight grid + QUANT_5, once with 4x4 weight grid + QUANT_12), simulates the
// ASTC decoder for each result, and emits whichever physical block has lower
// reconstruction error.
//
// OPTIMIZATION: Use [loop] instead of [unroll] for Mode B to reduce SPV size.
//
// Required macros (set before #include):
//   BLOCK_W, BLOCK_H, BLOCK_SIZE
//   GRID_FUNC_NAME       - top-level encoder function name
//
// Both modes use 6-byte Q256 endpoints (CEM 8 RGB Direct, 48 bits). Block
// mode bits:
//   - 5x5 grid + Q5: mode 242 (row 0: A=3, B=1, R=5, H=0, D=0)
//   - 4x4 grid + Q12: mode 593 (row 0: A=2, B=0, R=3, H=1, D=0)
//
// Bit budget identical for both (~123 bits used out of 128).

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

#include "astc_common.hlsl"

#ifndef GD_QUANT_DEFINED
#define GD_QUANT_DEFINED
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

#define GD_CEM_LDR_RGB_DIRECT 8
#define GD_SMALL_VAL 0.00001f

// =============================================================================
// Shared helpers
// =============================================================================

static float4 gd_eigen(float4x4 m)
{
    float4 v = float4(0.26726f, 0.80178f, 0.53452f, 0.0f);
    [unroll] for (int i = 0; i < 8; ++i) {
        v = mul(m, v);
        float l = length(v);
        if (l < GD_SMALL_VAL) return v;
        v = v / l;
        v = mul(m, v);
        l = length(v);
        if (l < GD_SMALL_VAL) return v;
        v = v / l;
    }
    return v;
}

// Bilinear sample of 4 nearest texels at continuous block-position
static float4 gd_sample_at(float4 texels[BLOCK_SIZE], uint gx, uint gy,
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

// =============================================================================
// Mode A: 5x5 grid + Q5 path (keep unroll - primary path)
// =============================================================================

static void gd_pca_full(float4 texels[BLOCK_SIZE], out float4 ep0, out float4 ep1)
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

    float4 axis = gd_eigen(cov);
    float lo =  1e31f, hi = -1e31f;
    [unroll] for (i = 0; i < BLOCK_SIZE; ++i) {
        float t = dot(texels[i] - mean, axis);
        lo = min(lo, t); hi = max(hi, t);
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

// 5x5 grid weight calc + quantization. Output: levels[25] in 0..4 (NOT scrambled).
static void gd_calc_5x5_levels(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1,
                                out uint levels[25])
{
    int i = 0;
    float4 vec_k = ep1 - ep0;
    float lensq = dot(vec_k, vec_k);
    if (lensq < GD_SMALL_VAL) {
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
            float4 sample = gd_sample_at(texels, gx, gy, scale_x, scale_y);
            float w = dot(vec_k, sample - ep0);
            uint idx = gy * 5u + gx;
            minw = min(minw, w); maxw = max(maxw, w);
            projw[idx] = w;
        }
    }
    float invlen = 1.0f / max(GD_SMALL_VAL, maxw - minw);
    [unroll] for (i = 0; i < 25; ++i) {
        float n = saturate((projw[i] - minw) * invlen);
        uint q = (uint)(n * 4.0f + 0.5f);
        levels[i] = clamp(q, 0u, 4u);
    }
}

// Simulate ASTC decoder for 5x5 grid in BwxBh block, return total squared error.
static float gd_recon_error_5x5(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1, uint levels[25])
{
    float dw[25];
    [unroll] for (uint i = 0; i < 25; ++i) dw[i] = (float)levels[i] / 4.0f;

    uint Bw = (uint)BLOCK_W;
    uint Bh = (uint)BLOCK_H;
    uint Ds = (1024u + (Bw - 1u) / 2u) / (Bw - 1u);
    uint Dt = (1024u + (Bh - 1u) / 2u) / (Bh - 1u);

    float total = 0.0f;
    [unroll] for (uint p = 0; p < BLOCK_SIZE; ++p) {
        uint s = p % Bw;
        uint t = p / Bw;
        uint cs = s * Ds;
        uint ct = t * Dt;
        uint gs = (cs * 4u + 32u) >> 6;
        uint gt = (ct * 4u + 32u) >> 6;
        uint js = gs >> 4;
        uint jt = gt >> 4;
        uint fs = gs & 15u;
        uint ft = gt & 15u;
        uint js1 = min(js + 1u, 4u);
        uint jt1 = min(jt + 1u, 4u);
        uint w11 = (fs * ft + 8u) >> 4;
        uint w10 = ft - w11;
        uint w01 = fs - w11;
        uint w00 = 16u - fs - ft + w11;

        float weight = ((float)w00 * dw[jt  * 5u + js ] +
                        (float)w01 * dw[jt  * 5u + js1] +
                        (float)w10 * dw[jt1 * 5u + js ] +
                        (float)w11 * dw[jt1 * 5u + js1]) / 16.0f;

        float4 recon = lerp(ep0, ep1, weight);
        float4 d = recon - texels[p];
        total += dot(d, d);
    }
    return total;
}

static void gd_bise_25_q5(uint scrambled[25], inout uint4 outputs)
{
    uint bitpos = 0;
    encode_quints(0, scrambled[ 0], scrambled[ 1], scrambled[ 2], outputs, bitpos);
    encode_quints(0, scrambled[ 3], scrambled[ 4], scrambled[ 5], outputs, bitpos);
    encode_quints(0, scrambled[ 6], scrambled[ 7], scrambled[ 8], outputs, bitpos);
    encode_quints(0, scrambled[ 9], scrambled[10], scrambled[11], outputs, bitpos);
    encode_quints(0, scrambled[12], scrambled[13], scrambled[14], outputs, bitpos);
    encode_quints(0, scrambled[15], scrambled[16], scrambled[17], outputs, bitpos);
    encode_quints(0, scrambled[18], scrambled[19], scrambled[20], outputs, bitpos);
    encode_quints(0, scrambled[21], scrambled[22], scrambled[23], outputs, bitpos);
    encode_quints(0, scrambled[24], 0, 0, outputs, bitpos);
}

static uint4 gd_pack_5x5_q5(float4 ep0, float4 ep1, uint levels[25])
{
    // Endpoints: 6 bytes @ Q256
    uint ep_quantized[8];
    uint4 e0q = (uint4)round(ep0);
    uint4 e1q = (uint4)round(ep1);
    ep_quantized[0] = e0q.r;  ep_quantized[1] = e1q.r;
    ep_quantized[2] = e0q.g;  ep_quantized[3] = e1q.g;
    ep_quantized[4] = e0q.b;  ep_quantized[5] = e1q.b;
    ep_quantized[6] = 0;      ep_quantized[7] = 0;
    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(ep_quantized, QUANT_256, ep_ise);

    // Scramble + ISE-pack weights
    uint scrambled[25];
    [unroll] for (uint i = 0; i < 25; ++i) {
        scrambled[i] = scramble_table[QUANT_5 * WEIGHT_QUANTIZE_NUM + levels[i]];
    }
    uint4 wt_ise = uint4(0,0,0,0);
    gd_bise_25_q5(scrambled, wt_ise);

    // Block mode 242: row 0, 5x5 grid, Q5, H=0, D=0
    const uint blockmode = 242u;

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
    phy.x |= (GD_CEM_LDR_RGB_DIRECT & 0xF) << 13;
    phy.x |=  (ep_ise.x        & 0x7FFF ) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |=  (ep_ise.y        & 0x7FFF ) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);
    return phy;
}

// =============================================================================
// Mode B: 4x4 grid + Q12 path (use [loop] for size reduction)
// =============================================================================

static void gd_pca_16(float4 samples[16], out float4 ep0, out float4 ep1)
{
    int i = 0;
    float4 mean = float4(0,0,0,0);
    [unroll] for (i = 0; i < 16; ++i) mean += samples[i];
    mean /= 16.0f;

    float4x4 cov = (float4x4)0;
    [unroll] for (int k = 0; k < 16; ++k) {
        float4 d = samples[k] - mean;
        [unroll] for (int a = 0; a < 4; ++a) {
            [unroll] for (int b = 0; b < 4; ++b) {
                cov[a][b] += d[a] * d[b];
            }
        }
    }
    cov /= 15.0f;

    float4 axis = gd_eigen(cov);
    float lo =  1e31f, hi = -1e31f;
    [unroll] for (i = 0; i < 16; ++i) {
        float t = dot(samples[i] - mean, axis);
        lo = min(lo, t); hi = max(hi, t);
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

// 4x4 grid weight calc + quantization. Output: levels[16] in 0..11.
static void gd_calc_4x4_levels(float4 samples[16], float4 ep0, float4 ep1,
                                out uint levels[16])
{
    int i = 0;
    float4 vec_k = ep1 - ep0;
    float lensq = dot(vec_k, vec_k);
    if (lensq < GD_SMALL_VAL) {
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
    float invlen = 1.0f / max(GD_SMALL_VAL, maxw - minw);
    [loop] for (i = 0; i < 16; ++i) {  // Changed: [unroll] -> [loop]
        float n = saturate((projw[i] - minw) * invlen);
        uint q = (uint)(n * 11.0f + 0.5f);
        levels[i] = clamp(q, 0u, 11u);
    }
}

// Simulate ASTC decoder for 4x4 grid in BwxBh block, return total squared error.
static float gd_recon_error_4x4(float4 texels[BLOCK_SIZE], float4 ep0, float4 ep1, uint levels[16])
{
    float dw[16];
    [loop] for (uint i = 0; i < 16; ++i) dw[i] = (float)levels[i] / 11.0f;  // Changed: [unroll] -> [loop]

    uint Bw = (uint)BLOCK_W;
    uint Bh = (uint)BLOCK_H;
    uint Ds = (1024u + (Bw - 1u) / 2u) / (Bw - 1u);
    uint Dt = (1024u + (Bh - 1u) / 2u) / (Bh - 1u);

    float total = 0.0f;
    [loop] for (uint p = 0; p < BLOCK_SIZE; ++p) {  // Changed: [unroll] -> [loop]
        uint s = p % Bw;
        uint t = p / Bw;
        uint cs = s * Ds;
        uint ct = t * Dt;
        uint gs = (cs * 3u + 32u) >> 6;
        uint gt = (ct * 3u + 32u) >> 6;
        uint js = gs >> 4;
        uint jt = gt >> 4;
        uint fs = gs & 15u;
        uint ft = gt & 15u;
        uint js1 = min(js + 1u, 3u);
        uint jt1 = min(jt + 1u, 3u);
        uint w11 = (fs * ft + 8u) >> 4;
        uint w10 = ft - w11;
        uint w01 = fs - w11;
        uint w00 = 16u - fs - ft + w11;

        float weight = ((float)w00 * dw[jt  * 4u + js ] +
                        (float)w01 * dw[jt  * 4u + js1] +
                        (float)w10 * dw[jt1 * 4u + js ] +
                        (float)w11 * dw[jt1 * 4u + js1]) / 16.0f;

        float4 recon = lerp(ep0, ep1, weight);
        float4 d = recon - texels[p];
        total += dot(d, d);
    }
    return total;
}

static void gd_bise_16_q12(uint scrambled[16], inout uint4 outputs)
{
    // QUANT_12: trits + 2 bits per value. 16 weights = 4 trit groups of 5 (last partial).
    uint bitpos = 0;
    encode_trits(2, scrambled[ 0], scrambled[ 1], scrambled[ 2], scrambled[ 3], scrambled[ 4], outputs, bitpos);
    encode_trits(2, scrambled[ 5], scrambled[ 6], scrambled[ 7], scrambled[ 8], scrambled[ 9], outputs, bitpos);
    encode_trits(2, scrambled[10], scrambled[11], scrambled[12], scrambled[13], scrambled[14], outputs, bitpos);
    encode_trits(2, scrambled[15], 0, 0, 0, 0, outputs, bitpos);
}

static uint4 gd_pack_4x4_q12(float4 ep0, float4 ep1, uint levels[16])
{
    uint ep_quantized[8];
    uint4 e0q = (uint4)round(ep0);
    uint4 e1q = (uint4)round(ep1);
    ep_quantized[0] = e0q.r;  ep_quantized[1] = e1q.r;
    ep_quantized[2] = e0q.g;  ep_quantized[3] = e1q.g;
    ep_quantized[4] = e0q.b;  ep_quantized[5] = e1q.b;
    ep_quantized[6] = 0;      ep_quantized[7] = 0;
    uint4 ep_ise = uint4(0,0,0,0);
    bise_endpoints(ep_quantized, QUANT_256, ep_ise);

    uint scrambled[16];
    [loop] for (uint i = 0; i < 16; ++i) {  // Changed: [unroll] -> [loop]
        scrambled[i] = scramble_table[QUANT_12 * WEIGHT_QUANTIZE_NUM + levels[i]];
    }
    uint4 wt_ise = uint4(0,0,0,0);
    gd_bise_16_q12(scrambled, wt_ise);

    // Block mode 593: row 0, 4x4 grid, Q12, H=1, D=0
    const uint blockmode = 593u;

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
    phy.x |= (GD_CEM_LDR_RGB_DIRECT & 0xF) << 13;
    phy.x |=  (ep_ise.x        & 0x7FFF ) << 17;
    phy.y |= ((ep_ise.x >> 15) & 0x1FFFF);
    phy.y |=  (ep_ise.y        & 0x7FFF ) << 17;
    phy.z |= ((ep_ise.y >> 15) & 0x1FFFF);
    return phy;
}

// =============================================================================
// Top-level: dual-mode encoder picks lower-error encoding per block
// =============================================================================

uint4 GRID_FUNC_NAME(float4 texels[BLOCK_SIZE])
{
    int i = 0;

    // ---- Mode A: 5x5 grid + Q5 ----
    float4 ep5_0, ep5_1;
    gd_pca_full(texels, ep5_0, ep5_1);
    uint levels5[25];
    gd_calc_5x5_levels(texels, ep5_0, ep5_1, levels5);
    float err5 = gd_recon_error_5x5(texels, ep5_0, ep5_1, levels5);

    // ---- Mode B: 4x4 grid + Q12 (via subsampling to 16) ----
    float4 samples_16[16];
    float scale_x_4x4 = (float)(BLOCK_W - 1) / 3.0f;
    float scale_y_4x4 = (float)(BLOCK_H - 1) / 3.0f;
    [unroll] for (uint gy = 0; gy < 4; ++gy) {
        [unroll] for (uint gx = 0; gx < 4; ++gx) {
            samples_16[gy * 4 + gx] = gd_sample_at(texels, gx, gy, scale_x_4x4, scale_y_4x4);
        }
    }
    float4 ep4_0, ep4_1;
    gd_pca_16(samples_16, ep4_0, ep4_1);
    uint levels4[16];
    gd_calc_4x4_levels(samples_16, ep4_0, ep4_1, levels4);
    float err4 = gd_recon_error_4x4(texels, ep4_0, ep4_1, levels4);

    // ---- Pick lower-error encoding ----
    if (err4 < err5) {
        return gd_pack_4x4_q12(ep4_0, ep4_1, levels4);
    } else {
        return gd_pack_5x5_q5(ep5_0, ep5_1, levels5);
    }
}
