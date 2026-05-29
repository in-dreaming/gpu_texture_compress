// compress/bc7.hlsl - Pure BC7 compression function (Mode 6 only)
// No global state, no texture reads.
// BC7 Mode 6: 1 subset, RGBA, 7 bits/component, 1 p-bit/endpoint, 4-bit indices
//
// Mode 6 bit layout (128 bits total):
//   [0..6]   = mode bits: 0000001 (bit 6 is the 1, identifying mode 6)
//   [7..62]  = color endpoints: 2 endpoints x 4 components x 7 bits = 56 bits
//              Order: R0(7), R1(7), G0(7), G1(7), B0(7), B1(7), A0(7), A1(7)
//   [63..64] = p-bits: P0(1), P1(1)
//   [65..127]= indices: anchor pixel (3 bits) + 15 pixels (4 bits) = 63 bits
//
// QualityLevel support:
//   0: Fast - PCA only, no LSQ refinement
//   1: Balanced - PCA + 1 LSQ iteration (default)
//   2: Quality - PCA + 3 LSQ iterations

#ifndef COMPRESS_BC7_HLSL
#define COMPRESS_BC7_HLSL

// Helper: compute PCA axis for RGBA data using power iteration
float4 BC7_ComputePCAAxis4(float4 pixels[16], float4 mean) {
    // Compute 4x4 covariance matrix (symmetric, 10 unique entries)
    // Order: xx, xy, xz, xw, yy, yz, yw, zz, zw, ww
    float cov[10];
    [unroll] for (int ci = 0; ci < 10; ci++) {
        cov[ci] = 0;
    }

    [unroll] for (int i = 0; i < 16; i++) {
        float4 d = pixels[i] - mean;
        cov[0] += d.x * d.x;
        cov[1] += d.x * d.y;
        cov[2] += d.x * d.z;
        cov[3] += d.x * d.w;
        cov[4] += d.y * d.y;
        cov[5] += d.y * d.z;
        cov[6] += d.y * d.w;
        cov[7] += d.z * d.z;
        cov[8] += d.z * d.w;
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
        if (len < 0.00001) {
            return float4(1, 0, 0, 0);
        }
        axis = newAxis / len;
    }

    return axis;
}

// Helper: write bits into a uint4 block at arbitrary bit position
void BC7_WriteBits(inout uint4 block, uint value, uint bitPos, uint numBits) {
    uint word = bitPos / 32;
    uint localBit = bitPos % 32;

    uint mask = (numBits >= 32) ? 0xFFFFFFFF : ((1u << numBits) - 1u);
    value &= mask;

    if (word == 0) {
        block.x |= (value << localBit);
        if (localBit + numBits > 32) {
            block.y |= (value >> (32 - localBit));
        }
    } else if (word == 1) {
        block.y |= (value << localBit);
        if (localBit + numBits > 32) {
            block.z |= (value >> (32 - localBit));
        }
    } else if (word == 2) {
        block.z |= (value << localBit);
        if (localBit + numBits > 32) {
            block.w |= (value >> (32 - localBit));
        }
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

// Helper: Least-squares endpoint refinement given fixed indices
void BC7_LSQ_RefineEndpoints(float4 pixels[16], uint indices[16], inout float4 ep0, inout float4 ep1) {
    float4 sumPixels[16];
    float weights[16];

    [unroll] for (int i = 0; i < 16; i++) {
        sumPixels[i] = float4(0, 0, 0, 0);
        weights[i] = 0.0;
    }

    [unroll] for (int pi = 0; pi < 16; pi++) {
        uint idx = indices[pi];
        sumPixels[idx] += pixels[pi];
        weights[idx] += 1.0;
    }

    // Recompute endpoints as average of assigned pixels
    if (weights[0] > 0.5) {
        ep0 = saturate(sumPixels[0] / weights[0]);
    }
    if (weights[15] > 0.5) {
        ep1 = saturate(sumPixels[15] / weights[15]);
    }
}

// Compress a 4x4 block of RGBA pixels into BC7 Mode 6 (128-bit block as uint4)
uint4 compress_bc7(float4 pixels[16]) {
    // Compute mean
    float4 mean = float4(0, 0, 0, 0);
    [unroll] for (int i = 0; i < 16; i++) {
        mean += pixels[i];
    }
    mean /= 16.0;

    // PCA on RGBA to find principal axis
    float4 axis = BC7_ComputePCAAxis4(pixels, mean);

    // Project pixels onto axis to find endpoint positions
    float minProj = 1e10;
    float maxProj = -1e10;
    [unroll] for (int pi = 0; pi < 16; pi++) {
        float proj = dot(pixels[pi] - mean, axis);
        minProj = min(minProj, proj);
        maxProj = max(maxProj, proj);
    }

    // Compute endpoints from projection extremes
    float4 endpoint0 = saturate(mean + axis * maxProj);
    float4 endpoint1 = saturate(mean + axis * minProj);

    // LSQ endpoint refinement loop - iterate based on quality level
    uint lsq_iterations = (QualityLevel == 0) ? 0 : ((QualityLevel == 1) ? 1 : 3);

    [loop] for (uint lsq_iter = 0; lsq_iter < lsq_iterations; lsq_iter++) {
        // Quantize endpoints to 7 bits (0..127)
        uint4 qep0 = uint4(
            min((uint)(endpoint0.x * 127.0 + 0.5), 127u),
            min((uint)(endpoint0.y * 127.0 + 0.5), 127u),
            min((uint)(endpoint0.z * 127.0 + 0.5), 127u),
            min((uint)(endpoint0.w * 127.0 + 0.5), 127u)
        );
        uint4 qep1 = uint4(
            min((uint)(endpoint1.x * 127.0 + 0.5), 127u),
            min((uint)(endpoint1.y * 127.0 + 0.5), 127u),
            min((uint)(endpoint1.z * 127.0 + 0.5), 127u),
            min((uint)(endpoint1.w * 127.0 + 0.5), 127u)
        );

        // P-bits
        uint pbit0 = ((uint)(endpoint0.x * 255.0 + 0.5)) & 1u;
        uint pbit1 = ((uint)(endpoint1.x * 255.0 + 0.5)) & 1u;

        // Reconstruct effective 8-bit endpoints
        float4 fep0 = float4(
            (float)((qep0.x << 1) | pbit0) / 255.0,
            (float)((qep0.y << 1) | pbit0) / 255.0,
            (float)((qep0.z << 1) | pbit0) / 255.0,
            (float)((qep0.w << 1) | pbit0) / 255.0
        );
        float4 fep1 = float4(
            (float)((qep1.x << 1) | pbit1) / 255.0,
            (float)((qep1.y << 1) | pbit1) / 255.0,
            (float)((qep1.z << 1) | pbit1) / 255.0,
            (float)((qep1.w << 1) | pbit1) / 255.0
        );

        // Compute indices
        uint indices[16];
        BC7_ComputeIndices(pixels, fep0, fep1, indices);

        // LSQ refinement for next iteration if not last
        if (lsq_iter < lsq_iterations - 1) {
            BC7_LSQ_RefineEndpoints(pixels, indices, endpoint0, endpoint1);
        }
    }

    // Final quantization
    uint4 qep0 = uint4(
        min((uint)(endpoint0.x * 127.0 + 0.5), 127u),
        min((uint)(endpoint0.y * 127.0 + 0.5), 127u),
        min((uint)(endpoint0.z * 127.0 + 0.5), 127u),
        min((uint)(endpoint0.w * 127.0 + 0.5), 127u)
    );
    uint4 qep1 = uint4(
        min((uint)(endpoint1.x * 127.0 + 0.5), 127u),
        min((uint)(endpoint1.y * 127.0 + 0.5), 127u),
        min((uint)(endpoint1.z * 127.0 + 0.5), 127u),
        min((uint)(endpoint1.w * 127.0 + 0.5), 127u)
    );

    // P-bits
    uint pbit0 = ((uint)(endpoint0.x * 255.0 + 0.5)) & 1u;
    uint pbit1 = ((uint)(endpoint1.x * 255.0 + 0.5)) & 1u;

    // Reconstruct effective 8-bit endpoints
    float4 fep0 = float4(
        (float)((qep0.x << 1) | pbit0) / 255.0,
        (float)((qep0.y << 1) | pbit0) / 255.0,
        (float)((qep0.z << 1) | pbit0) / 255.0,
        (float)((qep0.w << 1) | pbit0) / 255.0
    );
    float4 fep1 = float4(
        (float)((qep1.x << 1) | pbit1) / 255.0,
        (float)((qep1.y << 1) | pbit1) / 255.0,
        (float)((qep1.z << 1) | pbit1) / 255.0,
        (float)((qep1.w << 1) | pbit1) / 255.0
    );

    // Final index assignment
    uint indices[16];
    BC7_ComputeIndices(pixels, fep0, fep1, indices);

    // If anchor pixel (index 0) has MSB set, flip all indices and swap endpoints
    if (indices[0] >= 8) {
        [unroll] for (int fi = 0; fi < 16; fi++) {
            indices[fi] = 15 - indices[fi];
        }
        uint4 tmpEp = qep0;
        qep0 = qep1;
        qep1 = tmpEp;
        uint tmpP = pbit0;
        pbit0 = pbit1;
        pbit1 = tmpP;
    }

    // Pack into 128-bit block
    uint4 block = uint4(0, 0, 0, 0);
    uint bitPos = 0;

    // Mode bits [0..6]: 0000001 (mode 6 = bit position 6 is the '1')
    BC7_WriteBits(block, 64u, bitPos, 7);
    bitPos += 7;

    // Endpoints: R0(7), R1(7), G0(7), G1(7), B0(7), B1(7), A0(7), A1(7)
    BC7_WriteBits(block, qep0.x, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.x, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep0.y, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.y, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep0.z, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.z, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep0.w, bitPos, 7); bitPos += 7;
    BC7_WriteBits(block, qep1.w, bitPos, 7); bitPos += 7;

    // P-bits [63..64]
    BC7_WriteBits(block, pbit0, bitPos, 1); bitPos += 1;
    BC7_WriteBits(block, pbit1, bitPos, 1); bitPos += 1;

    // Indices: anchor pixel (3 bits, MSB implied 0), remaining 15 pixels (4 bits)
    BC7_WriteBits(block, indices[0] & 0x7, bitPos, 3); bitPos += 3;

    [unroll] for (int wi = 1; wi < 16; wi++) {
        BC7_WriteBits(block, indices[wi], bitPos, 4); bitPos += 4;
    }

    return block;
}

#endif // COMPRESS_BC7_HLSL
