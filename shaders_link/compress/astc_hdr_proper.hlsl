#ifndef ASTC_HDR_PROPER_HLSL
#define ASTC_HDR_PROPER_HLSL

//=============================================================================
// Proper HDR ASTC encoding with CEM 12 (HDR RGB Direct).
//
// Implements the full 8-mode precision encoder from astcenc, with a fallback
// flat representation when no precision mode fits.
//
// Reference: deps/astc-encoder/Source/astcenc_color_quantize.cpp
//   - quantize_hdr_rgb (line 1253)
//   - float_to_lns (astcenc_vecmathlib.h line 582)
//
// Algorithm overview:
//   1. Convert linear HDR floats to LNS (16-bit log-encoded values 0..65535)
//   2. Find major component (channel with largest color1 value); swizzle
//   3. Compute basis: a, b0, b1, c, d0, d1 (delta encoding)
//   4. Try modes 7..0 (high precision first); pick first that fits cutoffs
//   5. If none fit, use flat fallback (output[4]/[5] >= 128 signal)
//
// We use QUANT_256 (no further endpoint quantization), so quant_color and
// quantize_and_unquantize_retain_top_*_bits are identity for our purposes.
//=============================================================================

#include "astc_common.hlsl"

// ---------------------------------------------------------------------------
// LNS conversion (linear float -> 16-bit LNS integer-as-float)
// ---------------------------------------------------------------------------
float astc_float_to_lns(float v)
{
    if (!(v > 1.0 / 67108864.0)) return 0.0;
    if (v >= 65536.0) return 65535.0;

    float exp_f;
    float mant_f = frexp(v, exp_f);  // v = mant_f * 2^exp_f, mant_f in [0.5, 1)

    float a;
    float exp_out;
    if (exp_f < -13.0) {
        a = v * 33554432.0;
        exp_out = 0.0;
    } else {
        a = (mant_f - 0.5) * 4096.0;
        exp_out = exp_f + 14.0;
    }

    if (a < 384.0) {
        a = a * (4.0 / 3.0);
    } else if (a <= 1408.0) {
        a = a + 128.0;
    } else {
        a = (a + 512.0) * (4.0 / 5.0);
    }

    a = a + exp_out * 2048.0 + 1.0;
    if (a < 0.0) a = 0.0;
    if (a > 65535.0) a = 65535.0;
    return a;
}

// ---------------------------------------------------------------------------
// HDR mode tables (8 precision modes)
// ---------------------------------------------------------------------------
// mode_bits[mode]   = (a_bits, b_bits, c_bits, d_bits)
// mode_cutoffs[mode]= (b_cutoff, c_cutoff, d_cutoff, dabs_cutoff) in float space
// mode_scale[mode]  = factor applied to LNS values before quantization
// mode_rscale[mode] = inverse of mode_scale (LNS-units per quantized step)
//
// Mode index layout: bits/cutoffs encoded as static arrays (read by index)

static const uint hdr_a_bits_t[8] = { 9u, 9u, 10u, 10u, 11u, 11u, 12u, 12u };
static const uint hdr_b_bits_t[8] = { 7u, 8u,  6u,  7u,  8u,  6u,  7u,  6u };
static const uint hdr_c_bits_t[8] = { 6u, 6u,  7u,  7u,  6u,  8u,  7u,  7u };
static const uint hdr_d_bits_t[8] = { 7u, 6u,  7u,  6u,  5u,  6u,  5u,  6u };

static const float hdr_b_cutoff[8] = {
    16384.0, 32768.0,  4096.0,  8192.0,  8192.0,  2048.0,  2048.0,  1024.0
};
static const float hdr_c_cutoff[8] = {
    8192.0,   8192.0,  8192.0,  8192.0,  2048.0,  8192.0,  2048.0,  2048.0
};
static const float hdr_d_cutoff[8] = {
    8192.0,   4096.0,  4096.0,  2048.0,   512.0,  1024.0,   256.0,   512.0
};
static const float hdr_scale[8] = {
    1.0/128.0, 1.0/128.0, 1.0/64.0, 1.0/64.0, 1.0/32.0, 1.0/32.0, 1.0/16.0, 1.0/16.0
};
static const float hdr_rscale[8] = {
    128.0, 128.0, 64.0, 64.0, 32.0, 32.0, 16.0, 16.0
};

// HLSL doesn't allow indexing static arrays with non-literal in some cases.
// Use functions to dispatch by mode.
float get_hdr_b_cutoff(uint mode) {
    if (mode == 0u) return hdr_b_cutoff[0]; if (mode == 1u) return hdr_b_cutoff[1];
    if (mode == 2u) return hdr_b_cutoff[2]; if (mode == 3u) return hdr_b_cutoff[3];
    if (mode == 4u) return hdr_b_cutoff[4]; if (mode == 5u) return hdr_b_cutoff[5];
    if (mode == 6u) return hdr_b_cutoff[6]; return hdr_b_cutoff[7];
}
float get_hdr_c_cutoff(uint mode) {
    if (mode == 0u) return hdr_c_cutoff[0]; if (mode == 1u) return hdr_c_cutoff[1];
    if (mode == 2u) return hdr_c_cutoff[2]; if (mode == 3u) return hdr_c_cutoff[3];
    if (mode == 4u) return hdr_c_cutoff[4]; if (mode == 5u) return hdr_c_cutoff[5];
    if (mode == 6u) return hdr_c_cutoff[6]; return hdr_c_cutoff[7];
}
float get_hdr_d_cutoff(uint mode) {
    if (mode == 0u) return hdr_d_cutoff[0]; if (mode == 1u) return hdr_d_cutoff[1];
    if (mode == 2u) return hdr_d_cutoff[2]; if (mode == 3u) return hdr_d_cutoff[3];
    if (mode == 4u) return hdr_d_cutoff[4]; if (mode == 5u) return hdr_d_cutoff[5];
    if (mode == 6u) return hdr_d_cutoff[6]; return hdr_d_cutoff[7];
}
float get_hdr_scale(uint mode) {
    if (mode == 0u) return hdr_scale[0]; if (mode == 1u) return hdr_scale[1];
    if (mode == 2u) return hdr_scale[2]; if (mode == 3u) return hdr_scale[3];
    if (mode == 4u) return hdr_scale[4]; if (mode == 5u) return hdr_scale[5];
    if (mode == 6u) return hdr_scale[6]; return hdr_scale[7];
}
float get_hdr_rscale(uint mode) {
    if (mode == 0u) return hdr_rscale[0]; if (mode == 1u) return hdr_rscale[1];
    if (mode == 2u) return hdr_rscale[2]; if (mode == 3u) return hdr_rscale[3];
    if (mode == 4u) return hdr_rscale[4]; if (mode == 5u) return hdr_rscale[5];
    if (mode == 6u) return hdr_rscale[6]; return hdr_rscale[7];
}
uint get_hdr_b_bits(uint mode) {
    if (mode == 0u) return hdr_b_bits_t[0]; if (mode == 1u) return hdr_b_bits_t[1];
    if (mode == 2u) return hdr_b_bits_t[2]; if (mode == 3u) return hdr_b_bits_t[3];
    if (mode == 4u) return hdr_b_bits_t[4]; if (mode == 5u) return hdr_b_bits_t[5];
    if (mode == 6u) return hdr_b_bits_t[6]; return hdr_b_bits_t[7];
}
uint get_hdr_c_bits(uint mode) {
    if (mode == 0u) return hdr_c_bits_t[0]; if (mode == 1u) return hdr_c_bits_t[1];
    if (mode == 2u) return hdr_c_bits_t[2]; if (mode == 3u) return hdr_c_bits_t[3];
    if (mode == 4u) return hdr_c_bits_t[4]; if (mode == 5u) return hdr_c_bits_t[5];
    if (mode == 6u) return hdr_c_bits_t[6]; return hdr_c_bits_t[7];
}
uint get_hdr_d_bits(uint mode) {
    if (mode == 0u) return hdr_d_bits_t[0]; if (mode == 1u) return hdr_d_bits_t[1];
    if (mode == 2u) return hdr_d_bits_t[2]; if (mode == 3u) return hdr_d_bits_t[3];
    if (mode == 4u) return hdr_d_bits_t[4]; if (mode == 5u) return hdr_d_bits_t[5];
    if (mode == 6u) return hdr_d_bits_t[6]; return hdr_d_bits_t[7];
}

int round_to_int(float x) {
    return (int)(x + (x >= 0.0 ? 0.5 : -0.5));
}

// ---------------------------------------------------------------------------
// Try a single mode for HDR RGB direct encoding.
// Inputs: 6 LNS values (already swizzled so r0/r1 are the major component).
// Returns: success flag in `success`, output bytes in `out_bytes`.
// ---------------------------------------------------------------------------
void try_hdr_mode(
    uint mode,
    float r0_lns, float r1_lns,  // major component (after swizzle)
    float g0_lns, float g1_lns,  // mid component 1
    float b0r_lns, float b1r_lns,  // mid component 2
    uint majcomp,
    out bool success,
    out uint out_bytes[6])
{
    success = false;
    [unroll] for (int oi = 0; oi < 6; oi++) out_bytes[oi] = 0u;

    float a_base = r1_lns;
    float b0_base = a_base - g1_lns;
    float b1_base = a_base - b1r_lns;
    float c_base = a_base - r0_lns;
    float d0_base = a_base - b0_base - c_base - g0_lns;
    float d1_base = a_base - b1_base - c_base - b0r_lns;

    if (b0_base > get_hdr_b_cutoff(mode) || b1_base > get_hdr_b_cutoff(mode) ||
        c_base > get_hdr_c_cutoff(mode) ||
        abs(d0_base) > get_hdr_d_cutoff(mode) ||
        abs(d1_base) > get_hdr_d_cutoff(mode)) {
        return;
    }

    float scale = get_hdr_scale(mode);
    float rscale = get_hdr_rscale(mode);

    int b_intcutoff = 1 << (int)get_hdr_b_bits(mode);
    int c_intcutoff = 1 << (int)get_hdr_c_bits(mode);
    int d_intcutoff = 1 << ((int)get_hdr_d_bits(mode) - 1);

    // Quantize a (8 low bits + high bits packed elsewhere)
    int a_intval = round_to_int(a_base * scale);
    int a_lowbits = a_intval & 0xFF;
    int a_quantval = a_lowbits;  // QUANT_256 identity
    a_intval = (a_intval & ~0xFF) | a_quantval;
    float a_fval = float(a_intval) * rscale;

    // Recompute c
    float c_fval = a_fval - r0_lns;
    if (c_fval < 0.0) c_fval = 0.0;
    if (c_fval > 65535.0) c_fval = 65535.0;
    int c_intval = round_to_int(c_fval * scale);
    if (c_intval >= c_intcutoff) return;

    int c_lowbits = c_intval & 0x3F;
    c_lowbits |= ((int)mode & 1) << 7;
    c_lowbits |= (a_intval & 0x100) >> 2;  // bit at position 6 of c_lowbits

    int c_quantval = c_lowbits;  // QUANT_256 retain-top-2-bits identity
    c_intval = (c_intval & ~0x3F) | (c_quantval & 0x3F);
    c_fval = float(c_intval) * rscale;

    // Recompute b0, b1
    float b0_fval = a_fval - g1_lns;
    float b1_fval = a_fval - b1r_lns;
    if (b0_fval < 0.0) b0_fval = 0.0;
    if (b0_fval > 65535.0) b0_fval = 65535.0;
    if (b1_fval < 0.0) b1_fval = 0.0;
    if (b1_fval > 65535.0) b1_fval = 65535.0;
    int b0_intval = round_to_int(b0_fval * scale);
    int b1_intval = round_to_int(b1_fval * scale);

    if (b0_intval >= b_intcutoff || b1_intval >= b_intcutoff) return;

    int b0_lowbits = b0_intval & 0x3F;
    int b1_lowbits = b1_intval & 0x3F;

    int bit0;
    if (mode == 0u || mode == 1u || mode == 3u || mode == 4u || mode == 6u) {
        bit0 = (b0_intval >> 6) & 1;
    } else {  // 2, 5, 7
        bit0 = (a_intval >> 9) & 1;
    }

    int bit1;
    if (mode == 0u || mode == 1u || mode == 3u || mode == 4u || mode == 6u) {
        bit1 = (b1_intval >> 6) & 1;
    } else if (mode == 2u) {
        bit1 = (c_intval >> 6) & 1;
    } else {  // 5, 7
        bit1 = (a_intval >> 10) & 1;
    }

    b0_lowbits |= bit0 << 6;
    b1_lowbits |= bit1 << 6;
    b0_lowbits |= (((int)mode >> 1) & 1) << 7;
    b1_lowbits |= (((int)mode >> 2) & 1) << 7;

    int b0_quantval = b0_lowbits;
    int b1_quantval = b1_lowbits;
    b0_intval = (b0_intval & ~0x3F) | (b0_quantval & 0x3F);
    b1_intval = (b1_intval & ~0x3F) | (b1_quantval & 0x3F);
    float b0_fval_q = float(b0_intval) * rscale;
    float b1_fval_q = float(b1_intval) * rscale;

    // Recompute d0, d1 (signed)
    float d0_fval = a_fval - b0_fval_q - c_fval - g0_lns;
    float d1_fval = a_fval - b1_fval_q - c_fval - b0r_lns;
    if (d0_fval < -65535.0) d0_fval = -65535.0;
    if (d0_fval > 65535.0) d0_fval = 65535.0;
    if (d1_fval < -65535.0) d1_fval = -65535.0;
    if (d1_fval > 65535.0) d1_fval = 65535.0;

    int d0_intval = round_to_int(d0_fval * scale);
    int d1_intval = round_to_int(d1_fval * scale);
    if (abs(d0_intval) >= d_intcutoff || abs(d1_intval) >= d_intcutoff) return;

    int d0_lowbits = d0_intval & 0x1F;
    int d1_lowbits = d1_intval & 0x1F;

    int bit2;
    if (mode == 0u || mode == 2u) bit2 = (d0_intval >> 6) & 1;
    else if (mode == 1u || mode == 4u) bit2 = (b0_intval >> 7) & 1;
    else if (mode == 3u) bit2 = (a_intval >> 9) & 1;
    else if (mode == 5u) bit2 = (c_intval >> 7) & 1;
    else /* 6, 7 */ bit2 = (a_intval >> 11) & 1;

    int bit3;
    if (mode == 0u || mode == 2u) bit3 = (d1_intval >> 6) & 1;
    else if (mode == 1u || mode == 4u) bit3 = (b1_intval >> 7) & 1;
    else /* 3, 5, 6, 7 */ bit3 = (c_intval >> 6) & 1;

    int bit4, bit5;
    if (mode == 4u || mode == 6u) {
        bit4 = (a_intval >> 9) & 1;
        bit5 = (a_intval >> 10) & 1;
    } else {
        bit4 = (d0_intval >> 5) & 1;
        bit5 = (d1_intval >> 5) & 1;
    }

    d0_lowbits |= bit2 << 6;
    d1_lowbits |= bit3 << 6;
    d0_lowbits |= bit4 << 5;
    d1_lowbits |= bit5 << 5;
    d0_lowbits |= ((int)majcomp & 1) << 7;
    d1_lowbits |= (((int)majcomp >> 1) & 1) << 7;

    int d0_quantval = d0_lowbits;  // QUANT_256 retain-top-4-bits identity
    int d1_quantval = d1_lowbits;

    out_bytes[0] = (uint)(a_quantval & 0xFF);
    out_bytes[1] = (uint)(c_quantval & 0xFF);
    out_bytes[2] = (uint)(b0_quantval & 0xFF);
    out_bytes[3] = (uint)(b1_quantval & 0xFF);
    out_bytes[4] = (uint)(d0_quantval & 0xFF);
    out_bytes[5] = (uint)(d1_quantval & 0xFF);
    success = true;
}

// ---------------------------------------------------------------------------
// Encode HDR endpoints using full CEM 12 algorithm.
//   Input ep0/ep1 in linear HDR float (post-PCA + min/max projection)
//   Output 6 bytes encoded per ASTC HDR direct format
// ---------------------------------------------------------------------------
void astc_encode_hdr_endpoints(float3 ep0_in, float3 ep1_in, out uint output[6])
{
    // Convert to LNS
    float3 ep0_lns = float3(astc_float_to_lns(ep0_in.r), astc_float_to_lns(ep0_in.g), astc_float_to_lns(ep0_in.b));
    float3 ep1_lns = float3(astc_float_to_lns(ep1_in.r), astc_float_to_lns(ep1_in.g), astc_float_to_lns(ep1_in.b));

    float3 c0_bak = ep0_lns;
    float3 c1_bak = ep1_lns;

    // Find major component (channel with largest value in color1)
    uint majcomp;
    if (ep1_lns.r > ep1_lns.g && ep1_lns.r > ep1_lns.b) majcomp = 0u;
    else if (ep1_lns.g > ep1_lns.b) majcomp = 1u;
    else majcomp = 2u;

    // Swizzle so major is in lane 0
    float3 c0 = ep0_lns;
    float3 c1 = ep1_lns;
    if (majcomp == 1u) {
        c0 = ep0_lns.gbr; // swap r,g: actually swizzle (g, r, b) per astcenc
        c0 = float3(ep0_lns.g, ep0_lns.r, ep0_lns.b);
        c1 = float3(ep1_lns.g, ep1_lns.r, ep1_lns.b);
    } else if (majcomp == 2u) {
        c0 = float3(ep0_lns.b, ep0_lns.g, ep0_lns.r);
        c1 = float3(ep1_lns.b, ep1_lns.g, ep1_lns.r);
    }

    // Try modes 7..0
    bool found = false;
    uint result[6] = { 0u, 0u, 0u, 0u, 0u, 0u };

    [unroll] for (int mi = 0; mi < 8; mi++) {
        if (!found) {
            uint mode = (uint)(7 - mi);
            bool succ;
            uint cand[6];
            try_hdr_mode(mode, c0.x, c1.x, c0.y, c1.y, c0.z, c1.z, majcomp, succ, cand);
            if (succ) {
                [unroll] for (int oi = 0; oi < 6; oi++) result[oi] = cand[oi];
                found = true;
            }
        }
    }

    // Fallback flat encoding if no mode fit
    if (!found) {
        float vals[6];
        vals[0] = c0_bak.r; vals[1] = c1_bak.r;
        vals[2] = c0_bak.g; vals[3] = c1_bak.g;
        vals[4] = c0_bak.b; vals[5] = c1_bak.b;
        [unroll] for (int vi = 0; vi < 6; vi++) {
            if (vals[vi] < 0.0) vals[vi] = 0.0;
            if (vals[vi] > 65020.0) vals[vi] = 65020.0;
        }
        [unroll] for (int j = 0; j < 4; j++) {
            int idx = round_to_int(vals[j] * (1.0 / 256.0));
            if (idx < 0) idx = 0;
            if (idx > 255) idx = 255;
            result[j] = (uint)idx;
        }
        [unroll] for (int k = 4; k < 6; k++) {
            int idx = round_to_int(vals[k] * (1.0 / 512.0)) + 128;
            if (idx < 128) idx = 128;
            if (idx > 255) idx = 255;
            result[k] = (uint)idx;
        }
    }

    [unroll] for (int oi = 0; oi < 6; oi++) output[oi] = result[oi];
}

// ---------------------------------------------------------------------------
// Top-level: compress 4x4 HDR block with proper CEM 12 encoding.
// ---------------------------------------------------------------------------
uint4 astc_compress_4x4_hdr_proper(float4 hdr_pixels[16])
{
    // Sanitize + collect stats
    float3 min_val = float3(1e30, 1e30, 1e30);
    float3 max_val = float3(-1e30, -1e30, -1e30);
    float3 sum_rgb = float3(0, 0, 0);

    [unroll] for (int i = 0; i < 16; i++) {
        float3 p = hdr_pixels[i].rgb;
        if (!(p.r >= 0.0 && p.r < 65536.0)) p.r = 0.0;
        if (!(p.g >= 0.0 && p.g < 65536.0)) p.g = 0.0;
        if (!(p.b >= 0.0 && p.b < 65536.0)) p.b = 0.0;
        min_val = min(min_val, p);
        max_val = max(max_val, p);
        sum_rgb += p;
    }
    float3 avg_rgb = sum_rgb / 16.0;
    float3 range = max_val - min_val;
    if (dot(range, range) < 1e-8) {
        return astc_void_extent(float4(avg_rgb, 1.0));
    }

    // PCA in LNS (log) space — better suited for HDR
    float3 lns_pixels[16];
    float3 lns_mean = float3(0, 0, 0);
    [unroll] for (int j = 0; j < 16; j++) {
        float3 p = hdr_pixels[j].rgb;
        if (!(p.r >= 0.0)) p.r = 0.0;
        if (!(p.g >= 0.0)) p.g = 0.0;
        if (!(p.b >= 0.0)) p.b = 0.0;
        lns_pixels[j] = float3(log2(max(p.r, 1e-6)),
                               log2(max(p.g, 1e-6)),
                               log2(max(p.b, 1e-6)));
        lns_mean += lns_pixels[j];
    }
    lns_mean /= 16.0;

    float3 cov_diag = float3(0, 0, 0);
    float3 cov_off = float3(0, 0, 0);
    [unroll] for (int k = 0; k < 16; k++) {
        float3 d = lns_pixels[k] - lns_mean;
        cov_diag += d * d;
        cov_off += float3(d.x * d.y, d.x * d.z, d.y * d.z);
    }

    float3 axis = astc_compute_pca_axis(lns_mean, cov_diag, cov_off);

    float minp = 1e30, maxp = -1e30;
    [unroll] for (int m = 0; m < 16; m++) {
        float t = dot(lns_pixels[m] - lns_mean, axis);
        minp = min(minp, t);
        maxp = max(maxp, t);
    }

    float3 lns_ep0 = lns_mean + axis * minp;
    float3 lns_ep1 = lns_mean + axis * maxp;
    float3 ep0 = float3(exp2(lns_ep0.x), exp2(lns_ep0.y), exp2(lns_ep0.z));
    float3 ep1 = float3(exp2(lns_ep1.x), exp2(lns_ep1.y), exp2(lns_ep1.z));

    // Stable ordering: sum-darker endpoint as ep0
    if (ep0.r + ep0.g + ep0.b > ep1.r + ep1.g + ep1.b) {
        float3 tmp = ep0; ep0 = ep1; ep1 = tmp;
    }

    // Encode endpoints via full CEM 12 algorithm
    uint endpoints[6];
    astc_encode_hdr_endpoints(ep0, ep1, endpoints);

    // Compute per-pixel weights via projection in linear space
    float3 dir = ep1 - ep0;
    float lensq = dot(dir, dir);

    uint weights[16];
    [unroll] for (int n = 0; n < 16; n++) {
        float3 p = hdr_pixels[n].rgb;
        if (!(p.r >= 0.0)) p.r = 0.0;
        if (!(p.g >= 0.0)) p.g = 0.0;
        if (!(p.b >= 0.0)) p.b = 0.0;
        float t = (lensq < 1e-8) ? 0.0 : saturate(dot(p - ep0, dir) / lensq);
        uint qw = (uint)(t * 3.0 + 0.5);
        if (qw > 3u) qw = 3u;
        weights[n] = qw;
    }

    return astc_pack_block_with_mode_hdr(ASTC_BLOCK_MODE_4x4_Q4, endpoints, weights);
}

#endif // ASTC_HDR_PROPER_HLSL
