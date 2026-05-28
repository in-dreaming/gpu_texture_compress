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
    // Find min and max
    float minVal = values[0];
    float maxVal = values[0];
    [unroll] for (int i = 1; i < 16; i++) {
        minVal = min(minVal, values[i]);
        maxVal = max(maxVal, values[i]);
    }

    // Initial endpoints
    uint ep0 = (uint)(saturate(maxVal) * 255.0 + 0.5);
    uint ep1 = (uint)(saturate(minVal) * 255.0 + 0.5);

    if (ep0 == ep1) {
        if (ep0 < 255) ep0++;
        else ep1--;
    }

    // Try both 8-value and 6-value modes to see which is better
    uint best_indices[16];
    float best_error = 1e10;
    bool use_8value = true;

    // Try 8-value mode
    uint indices_8v[16];
    float error_8v;
    evaluate_8value(values, ep0, ep1, indices_8v, error_8v);

    // Also try swapped for 8-value
    uint indices_8v_swap[16];
    float error_8v_swap;
    if (ep1 < ep0) {
        evaluate_8value(values, ep1, ep0, indices_8v_swap, error_8v_swap);
        if (error_8v_swap < error_8v) {
            error_8v = error_8v_swap;
            [unroll] for (int i = 0; i < 16; i++) indices_8v[i] = indices_8v_swap[i];
            uint tmp = ep0;
            ep0 = ep1;
            ep1 = tmp;
        }
    }

    best_error = error_8v;
    [unroll] for (int i = 0; i < 16; i++) best_indices[i] = indices_8v[i];
    use_8value = true;

    // Try 6-value mode
    uint indices_6v[16];
    float error_6v;
    evaluate_6value(values, min(ep0, ep1), max(ep0, ep1), indices_6v, error_6v);
    if (error_6v < best_error) {
        best_error = error_6v;
        [unroll] for (int i = 0; i < 16; i++) best_indices[i] = indices_6v[i];
        use_8value = false;
        ep0 = min(ep0, ep1);
        ep1 = max(ep0, ep1);
    }

    // Local search around best endpoints (±3 range)
    [unroll] for (int d0 = -3; d0 <= 3; d0++) {
        [unroll] for (int d1 = -3; d1 <= 3; d1++) {
            uint try_ep0 = max(0, min(255, (int)ep0 + d0));
            uint try_ep1 = max(0, min(255, (int)ep1 + d1));

            if (try_ep0 == try_ep1) continue;

            uint try_indices[16];
            float try_error;

            if (use_8value && try_ep0 > try_ep1) {
                evaluate_8value(values, try_ep0, try_ep1, try_indices, try_error);
            } else if (!use_8value && try_ep0 <= try_ep1) {
                evaluate_6value(values, try_ep0, try_ep1, try_indices, try_error);
            } else {
                continue;
            }

            if (try_error < best_error) {
                best_error = try_error;
                [unroll] for (int i = 0; i < 16; i++) best_indices[i] = try_indices[i];
                ep0 = try_ep0;
                ep1 = try_ep1;
            }
        }
    }

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
