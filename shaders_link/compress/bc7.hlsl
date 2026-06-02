// compress/bc7.hlsl - Pure BC7 compression function (Mode 6 + Mode 1)
// No global state, no texture reads.
// BC7 Mode 6: 1 subset, RGBA, 7 bits/component, 1 p-bit/endpoint, 4-bit indices
// BC7 Mode 1: 2 subsets, RGB, 6 bits/component, 1 shared p-bit, 3-bit indices
//
// Mode 6 bit layout (128 bits total):
//   [0..6]   = mode bits: 0000001 (bit 6 is the 1, identifying mode 6)
//   [7..62]  = color endpoints: 2 endpoints x 4 components x 7 bits = 56 bits
//              Order: R0(7), R1(7), G0(7), G1(7), B0(7), B1(7), A0(7), A1(7)
//   [63..64] = p-bits: P0(1), P1(1)
//   [65..127]= indices: anchor pixel (3 bits) + 15 pixels (4 bits) = 63 bits
//
// Mode 1 bit layout:
//   [0..1]   = mode bits: 01 (mode 1)
//   [2..7]   = partition: 6 bits (0-63)
//   [8..43]  = color endpoints: 2 subsets x 2 endpoints x 3 components x 6 bits = 36 bits
//              Order: R0(6), R1(6), G0(6), G1(6), B0(6), B1(6) per subset
//   [44..45] = p-bits: P0(1), P1(1) (shared)
//   [46..92] = indices: subset 0 anchor (2 bits) + subset 0 others (3 bits x N)
//                       subset 1 anchor (2 bits) + subset 1 others (3 bits x M)
//
// QualityLevel support:
//   0: Fast - Mode 6 only, PCA only, no LSQ refinement
//   1: Balanced - Mode 6 + simple Mode 1 for high variance blocks
//   2: Quality - Full Mode 1 search + 3 LSQ iterations

#ifndef COMPRESS_BC7_HLSL
#define COMPRESS_BC7_HLSL

// ============================================================================
// BC7 Partition Tables (from DirectXTex BC7Encode.hlsl)
// ============================================================================

// For partition 0-63 (2-subset modes: 1, 3, 7)
// Each entry is a 16-bit mask: bit i = 0 if pixel i is in subset 0, 1 if in subset 1
static const uint g_bc7_partition_table[64] = {
    0xCCCC, 0x8888, 0xEEEE, 0xECC8, 0xC880, 0xFEEC, 0xFEC8, 0xEC80,
    0xC800, 0xFFEC, 0xFE80, 0xE800, 0xFFE8, 0xFF00, 0xFFF0, 0xF000,
    0xF710, 0x008E, 0x7100, 0x08CE, 0x008C, 0x7310, 0x3100, 0x8CCE,
    0x088C, 0x3110, 0x6666, 0x366C, 0x17E8, 0x0FF0, 0x718E, 0x399C,
    0xaaaa, 0xf0f0, 0x5a5a, 0x33cc, 0x3c3c, 0x55aa, 0x9696, 0xa55a,
    0x73ce, 0x13c8, 0x324c, 0x3bdc, 0x6996, 0xc33c, 0x9966, 0x0660,
    0x0272, 0x04e4, 0x4e40, 0x2720, 0xc936, 0x936c, 0x39c6, 0x639c,
    0x9336, 0x9cc6, 0x817e, 0xe718, 0xccf0, 0x0fcc, 0x7744, 0xee22
};

// Fixup indices for each partition (second subset anchor index)
static const uint g_bc7_fixup_index[64] = {
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15,  2,  8,  2,  2,  8,  8, 15,
     2,  8,  2,  2,  8,  8,  2,  2,
    15, 15,  6,  8,  2,  8, 15, 15,
     2,  8,  2,  2,  2, 15, 15,  6,
     6,  2,  6,  8, 15, 15,  2,  2,
    15, 15, 15, 15, 15,  2,  2, 15
};

// ============================================================================
// Helper Functions
// ============================================================================

// Helper: compute PCA axis for RGBA data using power iteration
float4 BC7_ComputePCAAxis4(float4 pixels[16], float4 mean) {
    // Compute 4x4 covariance matrix (symmetric, 10 unique entries)
    float cov[10];
    [unroll] for (int ci = 0; ci < 10; ci++) cov[ci] = 0;

    [unroll] for (int i = 0; i < 16; i++) {
        float4 d = pixels[i] - mean;
        cov[0] += d.x * d.x; cov[1] += d.x * d.y; cov[2] += d.x * d.z; cov[3] += d.x * d.w;
        cov[4] += d.y * d.y; cov[5] += d.y * d.z; cov[6] += d.y * d.w;
        cov[7] += d.z * d.z; cov[8] += d.z * d.w;
        cov[9] += d.w * d.w;
    }

    // Power iteration to find dominant eigenvector
    float4 axis = float4(0.26726, 0.80178, 0.53452, 0.12345);
    [unroll] for (int iter = 0; iter < 8; iter++) {
        float4 newAxis;
        newAxis.x = cov[0]*axis.x + cov[1]*axis.y + cov[2]*axis.z + cov[3]*axis.w;
        newAxis.y = cov[1]*axis.x + cov[4]*axis.y + cov[5]*axis.z + cov[6]*axis.w;
        newAxis.z = cov[2]*axis.x + cov[5]*axis.y + cov[7]*axis.z + cov[8]*axis.w;
        newAxis.w = cov[3]*axis.x + cov[6]*axis.y + cov[8]*axis.z + cov[9]*axis.w;
        float len = length(newAxis);
        if (len < 0.00001) return float4(1, 0, 0, 0);
        axis = newAxis / len;
    }
    return axis;
}

// Helper: compute block variance to decide if 2-subset mode might help
float BC7_ComputeBlockVariance(float4 pixels[16]) {
    float4 mean = float4(0, 0, 0, 0);
    [unroll] for (int i = 0; i < 16; i++) mean += pixels[i];
    mean /= 16.0;
    
    float variance = 0.0;
    [unroll] for (int j = 0; j < 16; j++) {
        float4 diff = pixels[j] - mean;
        variance += dot(diff.rgb, diff.rgb);
    }
    return variance / 16.0;
}

// Helper: get subset assignment for a pixel given partition index
uint BC7_GetSubset(uint partition_idx, uint pixel_idx) {
    return (g_bc7_partition_table[partition_idx] >> pixel_idx) & 1u;
}

// Helper: compute RGB variance split score for a partition
float BC7_EvaluatePartition(float4 pixels[16], uint partition_idx) {
    float3 mean[2] = {float3(0,0,0), float3(0,0,0)};
    uint count[2] = {0, 0};
    
    [unroll] for (uint i = 0; i < 16; i++) {
        uint subset = BC7_GetSubset(partition_idx, i);
        mean[subset] += pixels[i].rgb;
        count[subset]++;
    }
    
    mean[0] /= max(count[0], 1u);
    mean[1] /= max(count[1], 1u);
    
    float variance[2] = {0, 0};
    [unroll] for (uint j = 0; j < 16; j++) {
        uint subset = BC7_GetSubset(partition_idx, j);
        float3 diff = pixels[j].rgb - mean[subset];
        variance[subset] += dot(diff, diff);
    }
    return variance[0] + variance[1];
}

// Helper: write bits into a uint4 block at arbitrary bit position
void BC7_WriteBits(inout uint4 block, uint value, uint bitPos, uint numBits) {
    uint word = bitPos / 32;
    uint localBit = bitPos % 32;
    uint mask = (numBits >= 32) ? 0xFFFFFFFF : ((1u << numBits) - 1u);
    value &= mask;

    if (word == 0) {
        block.x |= (value << localBit);
        if (localBit + numBits > 32) block.y |= (value >> (32 - localBit));
    } else if (word == 1) {
        block.y |= (value << localBit);
        if (localBit + numBits > 32) block.z |= (value >> (32 - localBit));
    } else if (word == 2) {
        block.z |= (value << localBit);
        if (localBit + numBits > 32) block.w |= (value >> (32 - localBit));
    } else {
        block.w |= (value << localBit);
    }
}

// Helper: compute indices given fixed endpoints
void BC7_ComputeIndices(float4 pixels[16], float4 fep0, float4 fep1, out uint indices[16]) {
    float4 palette[16];
    [unroll] for (int p = 0; p < 16; p++) {
        float t = (float)p / 15.0;
        palette[p] = (1.0 - t) * fep0 + t * fep1;
    }
    [unroll] for (int qi = 0; qi < 16; qi++) {
        float bestDist = 1e10;
        uint bestIdx = 0;
        [unroll] for (int j = 0; j < 16; j++) {
            float4 diff = pixels[qi] - palette[j];
            float dist = dot(diff, diff);
            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = (uint)j;
            }
        }
        indices[qi] = bestIdx;
    }
}

// Helper: compute total squared error of indices+endpoints against pixels
float BC7_ComputeError(float4 pixels[16], uint indices[16], float4 fep0, float4 fep1) {
    float total = 0.0;
    [unroll] for (int ei = 0; ei < 16; ei++) {
        float t = (float)indices[ei] / 15.0;
        float4 reconstructed = (1.0 - t) * fep0 + t * fep1;
        float4 d = pixels[ei] - reconstructed;
        total += dot(d, d);
    }
    return total;
}

// Helper: Least-squares endpoint refinement given fixed indices
void BC7_LSQ_RefineEndpoints(float4 pixels[16], uint indices[16], inout float4 ep0, inout float4 ep1) {
    float A = 0.0, B = 0.0, C = 0.0;
    float4 X = float4(0, 0, 0, 0);
    float4 Y = float4(0, 0, 0, 0);

    [unroll] for (int pi = 0; pi < 16; pi++) {
        float t = (float)indices[pi] / 15.0;
        float oneMinusT = 1.0 - t;
        A += oneMinusT * oneMinusT;
        B += oneMinusT * t;
        C += t * t;
        X += pixels[pi] * oneMinusT;
        Y += pixels[pi] * t;
    }

    float det = A * C - B * B;
    if (abs(det) > 1e-6) {
        float invDet = 1.0 / det;
        ep0 = saturate((C * X - B * Y) * invDet);
        ep1 = saturate((A * Y - B * X) * invDet);
    }
}

// ============================================================================
// Mode 6: 1 subset, RGBA, 7-bit endpoints, 4-bit indices
// ============================================================================
// Returns the packed 128-bit block AND the encoder's reconstruction error so
// the caller can pick between Mode 6 and Mode 1.
uint4 BC7_Compress_Mode6_WithError(float4 pixels[16], out float out_error) {
    // Compute mean
    float4 mean = float4(0, 0, 0, 0);
    [unroll] for (int i = 0; i < 16; i++) mean += pixels[i];
    mean /= 16.0;

    // PCA on RGBA to find principal axis
    float4 axis = BC7_ComputePCAAxis4(pixels, mean);

    // Project pixels onto axis to find endpoint positions
    float minProj = 1e10, maxProj = -1e10;
    [unroll] for (int pi = 0; pi < 16; pi++) {
        float proj = dot(pixels[pi] - mean, axis);
        minProj = min(minProj, proj);
        maxProj = max(maxProj, proj);
    }

    // Compute endpoints from projection extremes
    float4 endpoint0 = saturate(mean + axis * maxProj);
    float4 endpoint1 = saturate(mean + axis * minProj);

    // LSQ endpoint refinement loop
    uint lsq_iterations = (QualityLevel == 0) ? 0u : ((QualityLevel == 1) ? 1u : 2u);
    [loop] for (uint lsq_iter = 0; lsq_iter < lsq_iterations; lsq_iter++) {
        uint4 qep0 = uint4(min((uint)(endpoint0.x * 127.0 + 0.5), 127u), min((uint)(endpoint0.y * 127.0 + 0.5), 127u),
                           min((uint)(endpoint0.z * 127.0 + 0.5), 127u), min((uint)(endpoint0.w * 127.0 + 0.5), 127u));
        uint4 qep1 = uint4(min((uint)(endpoint1.x * 127.0 + 0.5), 127u), min((uint)(endpoint1.y * 127.0 + 0.5), 127u),
                           min((uint)(endpoint1.z * 127.0 + 0.5), 127u), min((uint)(endpoint1.w * 127.0 + 0.5), 127u));
        uint pbit0 = ((uint)(endpoint0.x * 255.0 + 0.5)) & 1u;
        uint pbit1 = ((uint)(endpoint1.x * 255.0 + 0.5)) & 1u;
        float4 fep0 = float4((float)((qep0.x << 1) | pbit0) / 255.0, (float)((qep0.y << 1) | pbit0) / 255.0,
                             (float)((qep0.z << 1) | pbit0) / 255.0, (float)((qep0.w << 1) | pbit0) / 255.0);
        float4 fep1 = float4((float)((qep1.x << 1) | pbit1) / 255.0, (float)((qep1.y << 1) | pbit1) / 255.0,
                             (float)((qep1.z << 1) | pbit1) / 255.0, (float)((qep1.w << 1) | pbit1) / 255.0);
        uint indices[16];
        BC7_ComputeIndices(pixels, fep0, fep1, indices);
        float currentError = BC7_ComputeError(pixels, indices, fep0, fep1);
        float4 candidate0 = endpoint0, candidate1 = endpoint1;
        BC7_LSQ_RefineEndpoints(pixels, indices, candidate0, candidate1);
        uint4 cqep0 = uint4(min((uint)(candidate0.x * 127.0 + 0.5), 127u), min((uint)(candidate0.y * 127.0 + 0.5), 127u),
                            min((uint)(candidate0.z * 127.0 + 0.5), 127u), min((uint)(candidate0.w * 127.0 + 0.5), 127u));
        uint4 cqep1 = uint4(min((uint)(candidate1.x * 127.0 + 0.5), 127u), min((uint)(candidate1.y * 127.0 + 0.5), 127u),
                            min((uint)(candidate1.z * 127.0 + 0.5), 127u), min((uint)(candidate1.w * 127.0 + 0.5), 127u));
        uint cpbit0 = ((uint)(candidate0.x * 255.0 + 0.5)) & 1u;
        uint cpbit1 = ((uint)(candidate1.x * 255.0 + 0.5)) & 1u;
        float4 cfep0 = float4((float)((cqep0.x << 1) | cpbit0) / 255.0, (float)((cqep0.y << 1) | cpbit0) / 255.0,
                              (float)((cqep0.z << 1) | cpbit0) / 255.0, (float)((cqep0.w << 1) | cpbit0) / 255.0);
        float4 cfep1 = float4((float)((cqep1.x << 1) | cpbit1) / 255.0, (float)((cqep1.y << 1) | cpbit1) / 255.0,
                              (float)((cqep1.z << 1) | cpbit1) / 255.0, (float)((cqep1.w << 1) | cpbit1) / 255.0);
        uint candidateIndices[16];
        BC7_ComputeIndices(pixels, cfep0, cfep1, candidateIndices);
        float candidateError = BC7_ComputeError(pixels, candidateIndices, cfep0, cfep1);
        if (candidateError < currentError) {
            endpoint0 = candidate0;
            endpoint1 = candidate1;
        } else {
            break;
        }
    }

    // Final quantization
    uint4 qep0 = uint4(min((uint)(endpoint0.x * 127.0 + 0.5), 127u), min((uint)(endpoint0.y * 127.0 + 0.5), 127u),
                       min((uint)(endpoint0.z * 127.0 + 0.5), 127u), min((uint)(endpoint0.w * 127.0 + 0.5), 127u));
    uint4 qep1 = uint4(min((uint)(endpoint1.x * 127.0 + 0.5), 127u), min((uint)(endpoint1.y * 127.0 + 0.5), 127u),
                       min((uint)(endpoint1.z * 127.0 + 0.5), 127u), min((uint)(endpoint1.w * 127.0 + 0.5), 127u));
    uint pbit0 = ((uint)(endpoint0.x * 255.0 + 0.5)) & 1u;
    uint pbit1 = ((uint)(endpoint1.x * 255.0 + 0.5)) & 1u;

    // P-bit search
    if (QualityLevel >= 1) {
        float bestPbitError = 1e10;
        uint bestPbit0 = pbit0, bestPbit1 = pbit1;
        [unroll] for (uint pb0 = 0; pb0 < 2u; pb0++) {
            [unroll] for (uint pb1 = 0; pb1 < 2u; pb1++) {
                float4 trial_fep0 = float4((float)((qep0.x << 1) | pb0) / 255.0, (float)((qep0.y << 1) | pb0) / 255.0,
                                           (float)((qep0.z << 1) | pb0) / 255.0, (float)((qep0.w << 1) | pb0) / 255.0);
                float4 trial_fep1 = float4((float)((qep1.x << 1) | pb1) / 255.0, (float)((qep1.y << 1) | pb1) / 255.0,
                                           (float)((qep1.z << 1) | pb1) / 255.0, (float)((qep1.w << 1) | pb1) / 255.0);
                uint trial_indices[16];
                BC7_ComputeIndices(pixels, trial_fep0, trial_fep1, trial_indices);
                float trial_err = BC7_ComputeError(pixels, trial_indices, trial_fep0, trial_fep1);
                if (trial_err < bestPbitError) {
                    bestPbitError = trial_err;
                    bestPbit0 = pb0;
                    bestPbit1 = pb1;
                }
            }
        }
        pbit0 = bestPbit0;
        pbit1 = bestPbit1;
    }

    // Reconstruct effective 8-bit endpoints
    float4 fep0 = float4((float)((qep0.x << 1) | pbit0) / 255.0, (float)((qep0.y << 1) | pbit0) / 255.0,
                         (float)((qep0.z << 1) | pbit0) / 255.0, (float)((qep0.w << 1) | pbit0) / 255.0);
    float4 fep1 = float4((float)((qep1.x << 1) | pbit1) / 255.0, (float)((qep1.y << 1) | pbit1) / 255.0,
                         (float)((qep1.z << 1) | pbit1) / 255.0, (float)((qep1.w << 1) | pbit1) / 255.0);
    uint indices[16];
    BC7_ComputeIndices(pixels, fep0, fep1, indices);

    // Compute error for caller (before fixup, since fixup is a labelling change only).
    out_error = BC7_ComputeError(pixels, indices, fep0, fep1);

    // Anchor index fixup
    if (indices[0] >= 8) {
        [unroll] for (int fi = 0; fi < 16; fi++) indices[fi] = 15 - indices[fi];
        uint4 tmpEp = qep0; qep0 = qep1; qep1 = tmpEp;
        uint tmpP = pbit0; pbit0 = pbit1; pbit1 = tmpP;
    }

    // Pack into 128-bit block
    uint4 block = uint4(0, 0, 0, 0);
    uint bitPos = 0;
    BC7_WriteBits(block, 64u, bitPos, 7); bitPos += 7; // Mode 6
    BC7_WriteBits(block, qep0.x, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.x, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep0.y, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.y, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep0.z, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.z, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep0.w, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.w, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, pbit0, bitPos, 1); bitPos += 1;
    BC7_WriteBits(block, pbit1, bitPos, 1); bitPos += 1;
    BC7_WriteBits(block, indices[0] & 0x7, bitPos, 3); bitPos += 3;
    [unroll] for (int wi = 1; wi < 16; wi++) {
        BC7_WriteBits(block, indices[wi], bitPos, 4); bitPos += 4;
    }
    return block;
}

// ============================================================================
// Mode 1: 2 subsets, RGB, 6-bit endpoints + 1 shared p-bit per subset, 3-bit indices
// ============================================================================
// Endpoint expansion:
//   v6 = stored 6-bit value (0..63)
//   p  = shared p-bit (0..1)
//   v7 = (v6 << 1) | p       (7-bit combined)
//   v8 = (v7 << 1) | (v7 >> 6)  (8-bit expanded for palette)
//
// Per-subset, both endpoints share ONE p-bit. So Mode 1 has 2 p-bits total
// (P0 for subset 0, P1 for subset 1). Both endpoints in subset 0 use P0.
// ============================================================================

// Expand a 6-bit value + p-bit to 8-bit "decoded" endpoint for palette.
float BC7_Mode1_Expand6p(uint v6, uint p) {
    uint v7 = (v6 << 1) | (p & 1u);
    uint v8 = (v7 << 1) | (v7 >> 6);
    return (float)v8 / 255.0;
}

// Build the "stored" 8-bit form used by DirectXTex bit packing:
//   stored8 = (v6 << 2) | (p << 1)   so bits 7..2 = v6, bit 1 = p
uint BC7_Mode1_StoreForm(uint v6, uint p) {
    return ((v6 & 0x3Fu) << 2) | ((p & 1u) << 1);
}

uint4 BC7_Compress_Mode1(float4 pixels[16], out float out_error) {
    out_error = 1e30;

    // 1. Find best partition by minimizing per-subset variance.
    float bestVariance = 1e30;
    uint bestPartition = 0;
    uint partitionStep = (QualityLevel >= 2) ? 1u : 4u;
    for (uint p = 0; p < 64u; p += partitionStep) {
        float var = BC7_EvaluatePartition(pixels, p);
        if (var < bestVariance) {
            bestVariance = var;
            bestPartition = p;
        }
    }

    uint partition = bestPartition;

    // 2. Per-subset min/max RGB (initial endpoints).
    float3 subsetMin[2], subsetMax[2];
    subsetMin[0] = subsetMin[1] = float3(1, 1, 1);
    subsetMax[0] = subsetMax[1] = float3(0, 0, 0);
    [unroll] for (uint i = 0; i < 16; i++) {
        uint subset = BC7_GetSubset(partition, i);
        subsetMin[subset] = min(subsetMin[subset], pixels[i].rgb);
        subsetMax[subset] = max(subsetMax[subset], pixels[i].rgb);
    }

    // 3. Quantize endpoints to 6-bit (0..63). Try all 4 p-bit combinations later.
    //    For initial pass use p=0.
    uint3 qep[4];   // [0]=s0_lo, [1]=s0_hi, [2]=s1_lo, [3]=s1_hi (each is 6-bit RGB)
    [unroll] for (uint s = 0; s < 2; s++) {
        qep[s*2 + 0] = uint3(saturate(subsetMin[s]) * 63.0f + 0.5f);
        qep[s*2 + 1] = uint3(saturate(subsetMax[s]) * 63.0f + 0.5f);
    }

    // 4. P-bit search (4 combinations: 2 per subset). Pick lowest total error.
    uint bestP0 = 0, bestP1 = 0;
    float bestErr = 1e30;
    uint bestIndices[16];

    [unroll] for (uint pp0 = 0; pp0 < 2u; pp0++) {
        [unroll] for (uint pp1 = 0; pp1 < 2u; pp1++) {
            // Build expanded 8-bit endpoints for palette computation.
            float3 ep_s0_lo = float3(BC7_Mode1_Expand6p(qep[0].x, pp0),
                                     BC7_Mode1_Expand6p(qep[0].y, pp0),
                                     BC7_Mode1_Expand6p(qep[0].z, pp0));
            float3 ep_s0_hi = float3(BC7_Mode1_Expand6p(qep[1].x, pp0),
                                     BC7_Mode1_Expand6p(qep[1].y, pp0),
                                     BC7_Mode1_Expand6p(qep[1].z, pp0));
            float3 ep_s1_lo = float3(BC7_Mode1_Expand6p(qep[2].x, pp1),
                                     BC7_Mode1_Expand6p(qep[2].y, pp1),
                                     BC7_Mode1_Expand6p(qep[2].z, pp1));
            float3 ep_s1_hi = float3(BC7_Mode1_Expand6p(qep[3].x, pp1),
                                     BC7_Mode1_Expand6p(qep[3].y, pp1),
                                     BC7_Mode1_Expand6p(qep[3].z, pp1));

            // Compute indices and total error.
            uint trialIndices[16];
            float trialErr = 0;
            [unroll] for (uint pi = 0; pi < 16u; pi++) {
                uint subset = BC7_GetSubset(partition, pi);
                float3 lo = (subset == 0u) ? ep_s0_lo : ep_s1_lo;
                float3 hi = (subset == 0u) ? ep_s0_hi : ep_s1_hi;
                float3 t = pixels[pi].rgb;

                float bestDist = 1e30;
                uint bestIdx = 0;
                [unroll] for (uint idx = 0; idx < 8u; idx++) {
                    float w = (float)idx / 7.0f;
                    float3 pal = lerp(lo, hi, w);
                    float3 diff = t - pal;
                    float d = dot(diff, diff);
                    if (d < bestDist) {
                        bestDist = d;
                        bestIdx = idx;
                    }
                }
                trialIndices[pi] = bestIdx;
                trialErr += bestDist;
            }

            if (trialErr < bestErr) {
                bestErr = trialErr;
                bestP0 = pp0;
                bestP1 = pp1;
                [unroll] for (int ci = 0; ci < 16; ci++) bestIndices[ci] = trialIndices[ci];
            }
        }
    }

    out_error = bestErr;

    uint p0 = bestP0;
    uint p1 = bestP1;
    uint indices[16];
    [unroll] for (int ii = 0; ii < 16; ii++) indices[ii] = bestIndices[ii];

    // 5. Anchor index fixup (anchor 0 always for subset 0; fixup index for subset 1).
    //    If anchor MSB (bit 2 of 3-bit index) is set, flip indices in that subset
    //    and swap endpoints.
    uint fixup = g_bc7_fixup_index[partition];

    if (indices[0] >= 4u) {
        [unroll] for (uint k = 0; k < 16; k++) {
            if (BC7_GetSubset(partition, k) == 0u) indices[k] = 7u - indices[k];
        }
        uint3 tmp = qep[0]; qep[0] = qep[1]; qep[1] = tmp;
        // P-bit is shared per subset, so it stays with the subset; no swap needed.
    }
    if (indices[fixup] >= 4u) {
        [unroll] for (uint k = 0; k < 16; k++) {
            if (BC7_GetSubset(partition, k) == 1u) indices[k] = 7u - indices[k];
        }
        uint3 tmp = qep[2]; qep[2] = qep[3]; qep[3] = tmp;
    }

    // 6. Pack the block per DirectXTex BC7Encode.hlsl block_package1():
    //    Endpoints stored as 8-bit form: (v6 << 2) | (p << 1), then masked by 0xFC.
    //    Field positions in 128-bit block:
    //      [0..1]    mode = 0b01 (= 0x02)
    //      [2..7]    partition (6 bits)
    //      [8..13]   R0 (6 bits)
    //      [14..19]  R1 (6 bits)
    //      [20..25]  R2 (6 bits)
    //      [26..31]  R3 (6 bits)
    //      [32..37]  G0
    //      [38..43]  G1
    //      [44..49]  G2
    //      [50..55]  G3
    //      [56..61]  B0
    //      [62..67]  B1   (split across block.y/block.z)
    //      [68..73]  B2
    //      [74..79]  B3
    //      [80]      P0
    //      [81]      P1
    //      [82..127] indices (46 bits, layout depends on fixup)
    uint r0_st = BC7_Mode1_StoreForm(qep[0].x, p0);
    uint g0_st = BC7_Mode1_StoreForm(qep[0].y, p0);
    uint b0_st = BC7_Mode1_StoreForm(qep[0].z, p0);
    uint r1_st = BC7_Mode1_StoreForm(qep[1].x, p0);
    uint g1_st = BC7_Mode1_StoreForm(qep[1].y, p0);
    uint b1_st = BC7_Mode1_StoreForm(qep[1].z, p0);
    uint r2_st = BC7_Mode1_StoreForm(qep[2].x, p1);
    uint g2_st = BC7_Mode1_StoreForm(qep[2].y, p1);
    uint b2_st = BC7_Mode1_StoreForm(qep[2].z, p1);
    uint r3_st = BC7_Mode1_StoreForm(qep[3].x, p1);
    uint g3_st = BC7_Mode1_StoreForm(qep[3].y, p1);
    uint b3_st = BC7_Mode1_StoreForm(qep[3].z, p1);

    uint4 block;
    block.x = 0x02u | (partition << 2u)
            | ((r0_st & 0xFCu) << 6u)
            | ((r1_st & 0xFCu) << 12u)
            | ((r2_st & 0xFCu) << 18u)
            | ((r3_st & 0xFCu) << 24u);

    block.y = ((g0_st & 0xFCu) >> 2u)
            | ((g1_st & 0xFCu) << 4u)
            | ((g2_st & 0xFCu) << 10u)
            | ((g3_st & 0xFCu) << 16u)
            | ((b0_st & 0xFCu) << 22u)
            | ((b1_st & 0xFCu) << 28u);

    block.z = ((b1_st & 0xFCu) >> 4u)
            | ((b2_st & 0xFCu) << 2u)
            | ((b3_st & 0xFCu) << 8u)
            | ((r0_st & 0x02u) << 15u)   // P0 at bit 80
            | ((r2_st & 0x02u) << 16u);  // P1 at bit 81

    // Indices: 3 bits per pixel, 2 anchors with MSB-implied-zero (2 bits).
    // Bit positions in block.z/block.w depend on fixup index per partition.
    block.w = 0u;
    if (fixup == 15u) {
        // Anchors at pixels 0 and 15 (both 2-bit). Pixels 1..14 use 3 bits.
        block.z |= (indices[0] << 18u)
                |  (indices[1] << 20u)
                |  (indices[2] << 23u)
                |  (indices[3] << 26u)
                |  (indices[4] << 29u);
        block.w  = (indices[5])
                |  (indices[6] << 3u)
                |  (indices[7] << 6u)
                |  (indices[8] << 9u)
                |  (indices[9] << 12u)
                |  (indices[10] << 15u)
                |  (indices[11] << 18u)
                |  (indices[12] << 21u)
                |  (indices[13] << 24u)
                |  (indices[14] << 27u)
                |  (indices[15] << 30u);  // 2-bit anchor (MSB implied 0)
    } else if (fixup == 2u) {
        // Anchor at 2 means index[2] is 2-bit; 0 is 2-bit; 1, 3..15 are 3-bit.
        // Index 5 straddles block.z and block.w.
        block.z |= (indices[0] << 18u)
                |  (indices[1] << 20u)
                |  (indices[2] << 23u)   // 2-bit anchor
                |  (indices[3] << 25u)
                |  (indices[4] << 28u)
                |  (indices[5] << 31u);  // low bit of index[5]
        block.w  = (indices[5] >> 1u)
                |  (indices[6] << 2u)
                |  (indices[7] << 5u)
                |  (indices[8] << 8u)
                |  (indices[9] << 11u)
                |  (indices[10] << 14u)
                |  (indices[11] << 17u)
                |  (indices[12] << 20u)
                |  (indices[13] << 23u)
                |  (indices[14] << 26u)
                |  (indices[15] << 29u);
    } else if (fixup == 8u) {
        // Anchor at 8: indices 0 and 8 are 2-bit.
        block.z |= (indices[0] << 18u)
                |  (indices[1] << 20u)
                |  (indices[2] << 23u)
                |  (indices[3] << 26u)
                |  (indices[4] << 29u);
        block.w  = (indices[5])
                |  (indices[6] << 3u)
                |  (indices[7] << 6u)
                |  (indices[8] << 9u)   // 2-bit anchor
                |  (indices[9] << 11u)
                |  (indices[10] << 14u)
                |  (indices[11] << 17u)
                |  (indices[12] << 20u)
                |  (indices[13] << 23u)
                |  (indices[14] << 26u)
                |  (indices[15] << 29u);
    } else {
        // fixup == 6: anchors at 0 and 6.
        block.z |= (indices[0] << 18u)
                |  (indices[1] << 20u)
                |  (indices[2] << 23u)
                |  (indices[3] << 26u)
                |  (indices[4] << 29u);
        block.w  = (indices[5])
                |  (indices[6] << 3u)   // 2-bit anchor
                |  (indices[7] << 5u)
                |  (indices[8] << 8u)
                |  (indices[9] << 11u)
                |  (indices[10] << 14u)
                |  (indices[11] << 17u)
                |  (indices[12] << 20u)
                |  (indices[13] << 23u)
                |  (indices[14] << 26u)
                |  (indices[15] << 29u);
    }

    return block;
}

// ============================================================================
// Mode Selection and Error Computation
// ============================================================================

// Compute RGB error for Mode 1 (RGB only, no alpha)
float BC7_ComputeMode1Error(float4 pixels[16], uint4 block) {
    // Simple error estimation based on endpoints
    // This is a simplified version - full implementation would decompress
    float totalError = 0.0;
    
    // Extract partition from block
    uint partition = (block.x >> 2) & 0x3F;
    
    // Estimate error based on subset count
    // Mode 1 has 2 subsets, so generally better for complex blocks
    float variance = BC7_ComputeBlockVariance(pixels);
    
    // Mode 1 is better for high variance blocks (can use 2 subsets)
    // But we penalize slightly for the overhead
    return variance * 0.8;  // 0.8 factor favors Mode 1 for high variance
}

// Compute RGBA error for Mode 6
float BC7_ComputeMode6Error(float4 pixels[16], uint4 block) {
    float variance = BC7_ComputeBlockVariance(pixels);
    // Mode 6 has higher precision (7-bit + p-bit) and alpha support
    // But only 1 subset
    return variance;
}

// ============================================================================
// Main Entry Point
// ============================================================================
//
// Strategy:
//   QualityLevel 0 (fast):     Mode 6 only.
//   QualityLevel 1 (balanced): Mode 6 always; Mode 1 also tried for high-variance
//                              blocks; pick whichever has lower actual error.
//   QualityLevel 2 (best):     Mode 6 + Mode 1 (full 64-partition search).
//
// Note: Mode 1 has no alpha. For alpha-heavy blocks Mode 6 wins automatically
// because alpha quantization error inflates Mode 1's reported error vs the
// original 4-channel pixels (Mode 1 implicitly gives alpha=1).
uint4 compress_bc7(float4 pixels[16]) {
    if (QualityLevel == 0) {
        float dummy;
        return BC7_Compress_Mode6_WithError(pixels, dummy);
    }

    float err6;
    uint4 block6 = BC7_Compress_Mode6_WithError(pixels, err6);

    // Heuristic: only try Mode 1 if the block has enough variance and looks
    // like it has multi-modal content (worth a 2-subset partition).
    float blockVar = BC7_ComputeBlockVariance(pixels);
    bool tryMode1 = (blockVar > 0.005f);

    if (!tryMode1) return block6;

    float err1;
    uint4 block1 = BC7_Compress_Mode1(pixels, err1);

    // Mode 1 ignores alpha. Add a penalty equal to the alpha variance so we
    // don't switch away from Mode 6 on alpha-bearing content.
    float alphaMean = 0.0;
    [unroll] for (int ai = 0; ai < 16; ai++) alphaMean += pixels[ai].a;
    alphaMean /= 16.0;
    float alphaVar = 0.0;
    [unroll] for (int aj = 0; aj < 16; aj++) {
        float d = pixels[aj].a - alphaMean;
        alphaVar += d * d;
    }
    // If alpha is non-trivial, prefer Mode 6.
    if (alphaVar > 0.001f) return block6;

    return (err1 < err6) ? block1 : block6;
}

#endif // COMPRESS_BC7_HLSL
