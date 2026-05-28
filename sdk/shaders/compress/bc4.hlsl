// compress/bc4.hlsl - Pure BC4 compression with 8-value and 6-value mode selection
// BC4 format: 2x uint8 endpoints (16 bits) + 16x 3-bit indices (48 bits) = 64 bits
// Mode 1 (ep0 > ep1): 8-value interpolation
// Mode 2 (ep0 <= ep1): 6-value + 0 + 255

#ifndef COMPRESS_BC4_HLSL
#define COMPRESS_BC4_HLSL

// Evaluate 8-value mode (ep0 > ep1)
void evaluate_8value(in float values[16], in uint ep0, in uint ep1,
                     out uint indices[16], out float error) {
    float fep0 = (float)ep0 / 255.0;
    float fep1 = (float)ep1 / 255.0;

    float palette[8];
    palette[0] = fep0;
    palette[1] = fep1;
    palette[2] = (6.0 * fep0 + 1.0 * fep1) / 7.0;
    palette[3] = (5.0 * fep0 + 2.0 * fep1) / 7.0;
    palette[4] = (4.0 * fep0 + 3.0 * fep1) / 7.0;
    palette[5] = (3.0 * fep0 + 4.0 * fep1) / 7.0;
    palette[6] = (2.0 * fep0 + 5.0 * fep1) / 7.0;
    palette[7] = (1.0 * fep0 + 6.0 * fep1) / 7.0;

    error = 0.0;
    [unroll] for (int vi = 0; vi < 16; vi++) {
        float bestDist = 1e10;
        uint bestIdx = 0;
        [unroll] for (int j = 0; j < 8; j++) {
            float dist = abs(values[vi] - palette[j]);
            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = (uint)j;
            }
        }
        indices[vi] = bestIdx;
        error += bestDist * bestDist;
    }
}

// Evaluate 6-value mode (ep0 <= ep1, with 0 and 255)
void evaluate_6value(in float values[16], in uint ep0, in uint ep1,
                     out uint indices[16], out float error) {
    float fep0 = (float)ep0 / 255.0;
    float fep1 = (float)ep1 / 255.0;

    float palette[8];
    palette[0] = fep0;
    palette[1] = fep1;
    palette[2] = (4.0 * fep0 + 1.0 * fep1) / 5.0;
    palette[3] = (3.0 * fep0 + 2.0 * fep1) / 5.0;
    palette[4] = (2.0 * fep0 + 3.0 * fep1) / 5.0;
    palette[5] = (1.0 * fep0 + 4.0 * fep1) / 5.0;
    palette[6] = 0.0;  // Special black value
    palette[7] = 1.0;  // Special white value

    error = 0.0;
    [unroll] for (int vi = 0; vi < 16; vi++) {
        float bestDist = 1e10;
        uint bestIdx = 0;
        [unroll] for (int j = 0; j < 8; j++) {
            float dist = abs(values[vi] - palette[j]);
            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = (uint)j;
            }
        }
        indices[vi] = bestIdx;
        error += bestDist * bestDist;
    }
}

// Compress a 4x4 block of single-channel values into BC4
uint2 compress_bc4(float values[16]) {
    // Find min, max, and range
    float minVal = values[0];
    float maxVal = values[0];
    [unroll] for (int i = 1; i < 16; i++) {
        minVal = min(minVal, values[i]);
        maxVal = max(maxVal, values[i]);
    }

    float range = maxVal - minVal;

    // Constant block special case
    if (range < 0.001) {
        uint gray = (uint)(saturate((minVal + maxVal) * 0.5) * 255.0 + 0.5);
        uint ep0 = min((uint)255, gray + 1);
        uint ep1 = gray;

        uint indexLow = 0, indexHigh = 0;
        [unroll] for (int k = 0; k < 16; k++) {
            uint bitPos = (uint)k * 3;
            // All pixels use first palette entry (index 0)
        }

        uint packed_x = ep0 | (ep1 << 8) | ((indexLow & 0xFFFF) << 16);
        uint packed_y = (indexLow >> 16) | (indexHigh << 16);
        return uint2(packed_x, packed_y);
    }

    // Try multiple initial endpoint candidates
    uint best_indices[16];
    float best_error = 1e10;
    uint best_ep0 = 128, best_ep1 = 128;

    // Macro: Try both modes for a given endpoint pair
    #define TRY_ENDPOINTS(ep0, ep1) \
    { \
        uint try_indices_8v[16], try_indices_6v[16]; \
        float try_error_8v, try_error_6v; \
        if (ep0 > ep1) { \
            evaluate_8value(values, ep0, ep1, try_indices_8v, try_error_8v); \
            if (try_error_8v < best_error) { \
                best_error = try_error_8v; \
                [unroll] for (int i = 0; i < 16; i++) best_indices[i] = try_indices_8v[i]; \
                best_ep0 = ep0; \
                best_ep1 = ep1; \
            } \
        } \
        if (ep0 <= ep1) { \
            evaluate_6value(values, ep0, ep1, try_indices_6v, try_error_6v); \
            if (try_error_6v < best_error) { \
                best_error = try_error_6v; \
                [unroll] for (int i = 0; i < 16; i++) best_indices[i] = try_indices_6v[i]; \
                best_ep0 = ep0; \
                best_ep1 = ep1; \
            } \
        } \
    }

    // Candidate 1: min/max
    {
        uint try_ep0 = (uint)(saturate(maxVal) * 255.0 + 0.5);
        uint try_ep1 = (uint)(saturate(minVal) * 255.0 + 0.5);
        TRY_ENDPOINTS(try_ep0, try_ep1);
        TRY_ENDPOINTS(try_ep1, try_ep0);  // Also try flipped
    }

    // Candidate 2: median-based split (25%-75% quartiles)
    {
        uint med_ep0 = (uint)(saturate(minVal + range * 0.75) * 255.0 + 0.5);
        uint med_ep1 = (uint)(saturate(minVal + range * 0.25) * 255.0 + 0.5);
        TRY_ENDPOINTS(med_ep0, med_ep1);
        TRY_ENDPOINTS(med_ep1, med_ep0);  // Also try flipped
    }

    // Candidate 3: tertiles (33%-67%)
    {
        uint ter_ep0 = (uint)(saturate(minVal + range * 0.67) * 255.0 + 0.5);
        uint ter_ep1 = (uint)(saturate(minVal + range * 0.33) * 255.0 + 0.5);
        TRY_ENDPOINTS(ter_ep0, ter_ep1);
        TRY_ENDPOINTS(ter_ep1, ter_ep0);  // Also try flipped
    }

    // Candidate 4: deciles (10%-90%)
    {
        uint dec_ep0 = (uint)(saturate(minVal + range * 0.90) * 255.0 + 0.5);
        uint dec_ep1 = (uint)(saturate(minVal + range * 0.10) * 255.0 + 0.5);
        TRY_ENDPOINTS(dec_ep0, dec_ep1);
        TRY_ENDPOINTS(dec_ep1, dec_ep0);  // Also try flipped
    }

    // Coarse local search (±16 step-2 around best)
    [unroll] for (int d0 = -16; d0 <= 16; d0 += 2) {
        [unroll] for (int d1 = -16; d1 <= 16; d1 += 2) {
            uint try_ep0 = max(0, min(255, (int)best_ep0 + d0));
            uint try_ep1 = max(0, min(255, (int)best_ep1 + d1));

            if (try_ep0 == try_ep1) continue;

            uint try_indices[16];
            float try_error;

            if (try_ep0 > try_ep1) {
                evaluate_8value(values, try_ep0, try_ep1, try_indices, try_error);
                if (try_error < best_error) {
                    best_error = try_error;
                    [unroll] for (int i = 0; i < 16; i++) best_indices[i] = try_indices[i];
                    best_ep0 = try_ep0;
                    best_ep1 = try_ep1;
                }
            }

            if (try_ep0 <= try_ep1) {
                evaluate_6value(values, try_ep0, try_ep1, try_indices, try_error);
                if (try_error < best_error) {
                    best_error = try_error;
                    [unroll] for (int i = 0; i < 16; i++) best_indices[i] = try_indices[i];
                    best_ep0 = try_ep0;
                    best_ep1 = try_ep1;
                }
            }
        }
    }

    // Fine-grain local search (±2 step-1)
    [unroll] for (int d0 = -2; d0 <= 2; d0++) {
        [unroll] for (int d1 = -2; d1 <= 2; d1++) {
            uint try_ep0 = max(0, min(255, (int)best_ep0 + d0));
            uint try_ep1 = max(0, min(255, (int)best_ep1 + d1));

            if (try_ep0 == try_ep1) continue;

            uint try_indices[16];
            float try_error;

            if (try_ep0 > try_ep1) {
                evaluate_8value(values, try_ep0, try_ep1, try_indices, try_error);
                if (try_error < best_error) {
                    best_error = try_error;
                    [unroll] for (int i = 0; i < 16; i++) best_indices[i] = try_indices[i];
                    best_ep0 = try_ep0;
                    best_ep1 = try_ep1;
                }
            }

            if (try_ep0 <= try_ep1) {
                evaluate_6value(values, try_ep0, try_ep1, try_indices, try_error);
                if (try_error < best_error) {
                    best_error = try_error;
                    [unroll] for (int i = 0; i < 16; i++) best_indices[i] = try_indices[i];
                    best_ep0 = try_ep0;
                    best_ep1 = try_ep1;
                }
            }
        }
    }

    #undef TRY_ENDPOINTS

    uint ep0 = best_ep0;
    uint ep1 = best_ep1;

    // Pack into 64 bits
    uint indexLow = 0;
    uint indexHigh = 0;

    [unroll] for (int k = 0; k < 16; k++) {
        uint bitPos = (uint)k * 3;
        if (bitPos < 32) {
            indexLow |= (best_indices[k] << bitPos);
            if (bitPos > 29) {
                uint bitsInLow = 32 - bitPos;
                indexHigh |= (best_indices[k] >> bitsInLow);
            }
        } else {
            indexHigh |= (best_indices[k] << (bitPos - 32));
        }
    }

    uint packed_x = ep0 | (ep1 << 8) | ((indexLow & 0xFFFF) << 16);
    uint packed_y = (indexLow >> 16) | (indexHigh << 16);

    return uint2(packed_x, packed_y);
}

#endif // COMPRESS_BC4_HLSL
