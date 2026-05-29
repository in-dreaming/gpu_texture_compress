// compress/bc6h.hlsl - BC6H compression with improved PCA-based endpoints
// BC6H format: 128-bit block for HDR (half-float) RGB textures
// Uses Mode 11 (one region, unsigned, 10-bit endpoints, 4-bit indices)

#ifndef COMPRESS_BC6H_HLSL
#define COMPRESS_BC6H_HLSL

// Helper: write bits into a uint4 block at arbitrary bit position
void BC6H_WriteBits(inout uint4 block, uint value, uint bitPos, uint numBits) {
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

// Compute PCA axis for HDR RGB data
float3 BC6H_ComputePCAAxis(float3 pixels[16], float3 mean) {
    // Covariance matrix (symmetric 3x3: xx, xy, xz, yy, yz, zz)
    float cov[6] = {0, 0, 0, 0, 0, 0};

    [unroll] for (int i = 0; i < 16; i++) {
        float3 d = pixels[i] - mean;
        cov[0] += d.x * d.x;  // xx
        cov[1] += d.x * d.y;  // xy
        cov[2] += d.x * d.z;  // xz
        cov[3] += d.y * d.y;  // yy
        cov[4] += d.y * d.z;  // yz
        cov[5] += d.z * d.z;  // zz
    }

    // Power iteration to find dominant eigenvector
    float3 axis = normalize(float3(1.0, 1.0, 1.0));

    [unroll] for (int iter = 0; iter < 4; iter++) {
        float3 newAxis;
        newAxis.x = cov[0] * axis.x + cov[1] * axis.y + cov[2] * axis.z;
        newAxis.y = cov[1] * axis.x + cov[3] * axis.y + cov[4] * axis.z;
        newAxis.z = cov[2] * axis.x + cov[4] * axis.y + cov[5] * axis.z;

        float len = length(newAxis);
        if (len < 0.00001) return float3(1, 0, 0);

        axis = newAxis / len;
    }

    return axis;
}

// BC6H palette weights (shared with BC7 Mode 6)
static const uint aWeight4[16] = {0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64};

// Helper: Unquantize a 10-bit BC6H endpoint back to F16 integer space
uint BC6H_UnquantizeF16(uint q) {
    if (q == 0) return 0;
    if (q >= 1023) return 0xFFFF;
    return ((q << 16) + 0x8000) >> 10;  // (q << 6) + 32 in fractional form
}

// LSQ-fit endpoints to current index assignments
// Given fixed indices, solve for best endpoints using least-squares
void BC6H_LSQFitEndpoints(float3 pixels[16], uint indices[16], out float3 endpoint0, out float3 endpoint1) {
    // Compute weights: w0[i] = (64 - aWeight4[idx[i]]) / 64.0, w1[i] = aWeight4[idx[i]] / 64.0
    float w0[16];
    float w1[16];
    [unroll] for (int i = 0; i < 16; i++) {
        uint w1_int = aWeight4[indices[i]];
        float w1_f = (float)w1_int / 64.0;
        w1[i] = w1_f;
        w0[i] = 1.0 - w1_f;
    }

    // Accumulate matrix and vector for each channel
    float A00 = 0, A01 = 0, A11 = 0;
    [unroll] for (int i = 0; i < 16; i++) {
        A00 += w0[i] * w0[i];
        A01 += w0[i] * w1[i];
        A11 += w1[i] * w1[i];
    }

    // Solve per-channel using 2x2 inverse
    endpoint0 = float3(0, 0, 0);
    endpoint1 = float3(0, 0, 0);

    float det = A00 * A11 - A01 * A01;
    if (det < 0.00001) {
        // Singular: return midpoint
        float3 sum = float3(0, 0, 0);
        [unroll] for (int i = 0; i < 16; i++) sum += pixels[i];
        endpoint0 = sum / 16.0;
        endpoint1 = sum / 16.0;
        return;
    }

    [unroll] for (int ch = 0; ch < 3; ch++) {
        float b0 = 0, b1 = 0;
        [unroll] for (int i = 0; i < 16; i++) {
            float pix = (ch == 0) ? pixels[i].x : (ch == 1) ? pixels[i].y : pixels[i].z;
            b0 += w0[i] * pix;
            b1 += w1[i] * pix;
        }

        float ep0 = (b0 * A11 - b1 * A01) / det;
        float ep1 = (b1 * A00 - b0 * A01) / det;

        if (ch == 0) {
            endpoint0.x = ep0;
            endpoint1.x = ep1;
        } else if (ch == 1) {
            endpoint0.y = ep0;
            endpoint1.y = ep1;
        } else {
            endpoint0.z = ep0;
            endpoint1.z = ep1;
        }
    }
}

// Compress a 4x4 block of HDR RGB pixels into BC6H (Mode 11)
uint4 compress_bc6h(float3 pixels[16]) {
    // Compute mean
    float3 mean = float3(0, 0, 0);
    [unroll] for (int i = 0; i < 16; i++) {
        mean += pixels[i];
    }
    mean /= 16.0;

    // Clamp to non-negative (unsigned BC6H)
    [unroll] for (int i = 0; i < 16; i++) {
        pixels[i] = max(pixels[i], float3(0, 0, 0));
    }
    mean = max(mean, float3(0, 0, 0));

    // PCA to find principal color direction
    float3 axis = BC6H_ComputePCAAxis(pixels, mean);

    // Project pixels onto axis
    float minProj = 1e10;
    float maxProj = -1e10;
    [unroll] for (int pi = 0; pi < 16; pi++) {
        float proj = dot(pixels[pi] - mean, axis);
        minProj = min(minProj, proj);
        maxProj = max(maxProj, proj);
    }

    // Compute endpoints in float space
    float3 endpoint0 = mean + axis * maxProj;
    float3 endpoint1 = mean + axis * minProj;

    // Quantize endpoints to 10-bit BC6H space via F16 bit patterns
    // BC6H stores F16 bit patterns as 10-bit quantized values
    // Formula: q = f32tof16(floatValue) / 31
    // This maps the F16 range [0, 0x7BFF=31743] to [0, 1023]
    uint3 ep0 = uint3(
        min((uint)(f32tof16(endpoint0.x)) / 31u, 1023u),
        min((uint)(f32tof16(endpoint0.y)) / 31u, 1023u),
        min((uint)(f32tof16(endpoint0.z)) / 31u, 1023u)
    );
    uint3 ep1 = uint3(
        min((uint)(f32tof16(endpoint1.x)) / 31u, 1023u),
        min((uint)(f32tof16(endpoint1.y)) / 31u, 1023u),
        min((uint)(f32tof16(endpoint1.z)) / 31u, 1023u)
    );

    // Unquantize endpoints back to F16 bits for palette generation
    uint3 f16_ep0 = uint3(
        BC6H_UnquantizeF16(ep0.x),
        BC6H_UnquantizeF16(ep0.y),
        BC6H_UnquantizeF16(ep0.z)
    );
    uint3 f16_ep1 = uint3(
        BC6H_UnquantizeF16(ep1.x),
        BC6H_UnquantizeF16(ep1.y),
        BC6H_UnquantizeF16(ep1.z)
    );

    // Scale F16 values back (multiply by 31 and shift)
    f16_ep0 = (f16_ep0 * 31u) >> 6;
    f16_ep1 = (f16_ep1 * 31u) >> 6;

    // Generate 16-level palette using BC6H weight table in F16 space
    float3 palette[16];
    [unroll] for (int p = 0; p < 16; p++) {
        uint w1 = aWeight4[p];
        uint w0 = 64u - w1;

        // Compute weighted F16 endpoint for each channel
        uint f16_p_r = (f16_ep0.x * w0 + f16_ep1.x * w1 + 32) >> 6;
        uint f16_p_g = (f16_ep0.y * w0 + f16_ep1.y * w1 + 32) >> 6;
        uint f16_p_b = (f16_ep0.z * w0 + f16_ep1.z * w1 + 32) >> 6;

        // Convert F16 bits back to float
        palette[p].x = f16tof32(f16_p_r);
        palette[p].y = f16tof32(f16_p_g);
        palette[p].z = f16tof32(f16_p_b);
    }

    // Assign indices using palette
    uint indices[16];
    [unroll] for (int qi = 0; qi < 16; qi++) {
        float bestDist = 1e10;
        uint bestIdx = 0;
        [unroll] for (int j = 0; j < 16; j++) {
            float3 diff = pixels[qi] - palette[j];
            float dist = dot(diff, diff);
            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = (uint)j;
            }
        }
        indices[qi] = bestIdx;
    }

    // Iterative LSQ endpoint refinement with QualityLevel-based iteration count
    // QualityLevel 0: 0 iterations (fast, just use PCA endpoints)
    // QualityLevel 1: 1 iteration (balanced)
    // QualityLevel 2: 3 iterations (quality)
    int lsq_iterations = (QualityLevel == 0) ? 0 : ((QualityLevel == 1) ? 1 : 3);

    [loop] for (int iter = 0; iter < lsq_iterations; iter++) {
        // Fit new endpoints using LSQ
        float3 lsq_ep0, lsq_ep1;
        BC6H_LSQFitEndpoints(pixels, indices, lsq_ep0, lsq_ep1);

        // Apply endpoint inset to reduce quantization boundary overshoot
        float3 center = (lsq_ep0 + lsq_ep1) * 0.5;
        float inset = 1.0 / 16.0;  // for 16-entry palette
        lsq_ep0 = lsq_ep0 + (center - lsq_ep0) * inset;
        lsq_ep1 = lsq_ep1 + (center - lsq_ep1) * inset;

        // Clamp to non-negative for unsigned BC6H
        lsq_ep0 = max(lsq_ep0, float3(0, 0, 0));
        lsq_ep1 = max(lsq_ep1, float3(0, 0, 0));

        // Re-quantize endpoints to 10-bit F16 space
        uint3 new_ep0 = uint3(
            min((uint)(f32tof16(lsq_ep0.x)) / 31u, 1023u),
            min((uint)(f32tof16(lsq_ep0.y)) / 31u, 1023u),
            min((uint)(f32tof16(lsq_ep0.z)) / 31u, 1023u)
        );
        uint3 new_ep1 = uint3(
            min((uint)(f32tof16(lsq_ep1.x)) / 31u, 1023u),
            min((uint)(f32tof16(lsq_ep1.y)) / 31u, 1023u),
            min((uint)(f32tof16(lsq_ep1.z)) / 31u, 1023u)
        );

        // Unquantize back to F16 bits for palette generation
        uint3 new_f16_ep0 = uint3(
            BC6H_UnquantizeF16(new_ep0.x),
            BC6H_UnquantizeF16(new_ep0.y),
            BC6H_UnquantizeF16(new_ep0.z)
        );
        uint3 new_f16_ep1 = uint3(
            BC6H_UnquantizeF16(new_ep1.x),
            BC6H_UnquantizeF16(new_ep1.y),
            BC6H_UnquantizeF16(new_ep1.z)
        );

        // Scale F16 values back
        new_f16_ep0 = (new_f16_ep0 * 31u) >> 6;
        new_f16_ep1 = (new_f16_ep1 * 31u) >> 6;

        // Rebuild palette with new endpoints
        float3 new_palette[16];
        [unroll] for (int p = 0; p < 16; p++) {
            uint w1_val = aWeight4[p];
            uint w0_val = 64u - w1_val;

            uint new_f16_p_r = (new_f16_ep0.x * w0_val + new_f16_ep1.x * w1_val + 32) >> 6;
            uint new_f16_p_g = (new_f16_ep0.y * w0_val + new_f16_ep1.y * w1_val + 32) >> 6;
            uint new_f16_p_b = (new_f16_ep0.z * w0_val + new_f16_ep1.z * w1_val + 32) >> 6;

            new_palette[p].x = f16tof32(new_f16_p_r);
            new_palette[p].y = f16tof32(new_f16_p_g);
            new_palette[p].z = f16tof32(new_f16_p_b);
        }

        // Re-assign indices with new palette
        [unroll] for (int qi = 0; qi < 16; qi++) {
            float bestDist = 1e10;
            uint bestIdx = 0;
            [unroll] for (int j = 0; j < 16; j++) {
                float3 diff = pixels[qi] - new_palette[j];
                float dist = dot(diff, diff);
                if (dist < bestDist) {
                    bestDist = dist;
                    bestIdx = (uint)j;
                }
            }
            indices[qi] = bestIdx;
        }

        // Update endpoints for next iteration (or final packing)
        ep0 = new_ep0;
        ep1 = new_ep1;
    }

    // Anchor bit handling: if anchor (index 0) MSB set, flip indices and swap endpoints
    if (indices[0] >= 8) {
        [unroll] for (int fi = 0; fi < 16; fi++) {
            indices[fi] = 15 - indices[fi];
        }
        uint3 tmpEp = ep0;
        ep0 = ep1;
        ep1 = tmpEp;
    }

    // Pack into 128-bit block
    uint4 block = uint4(0, 0, 0, 0);
    uint bitPos = 0;

    // Mode bits [0..4] = 0x03 (mode 11 unsigned)
    BC6H_WriteBits(block, 3u, bitPos, 5);
    bitPos += 5;

    // Endpoints (R0, G0, B0, R1, G1, B1 - 10 bits each)
    BC6H_WriteBits(block, ep0.x, bitPos, 10); bitPos += 10;
    BC6H_WriteBits(block, ep0.y, bitPos, 10); bitPos += 10;
    BC6H_WriteBits(block, ep0.z, bitPos, 10); bitPos += 10;
    BC6H_WriteBits(block, ep1.x, bitPos, 10); bitPos += 10;
    BC6H_WriteBits(block, ep1.y, bitPos, 10); bitPos += 10;
    BC6H_WriteBits(block, ep1.z, bitPos, 10); bitPos += 10;

    // Indices: anchor pixel (3 bits, MSB implicit 0), then 15 pixels (4 bits each)
    BC6H_WriteBits(block, indices[0] & 0x7, bitPos, 3);
    bitPos += 3;

    [unroll] for (int wi = 1; wi < 16; wi++) {
        BC6H_WriteBits(block, indices[wi], bitPos, 4);
        bitPos += 4;
    }

    return block;
}

#endif // COMPRESS_BC6H_HLSL
