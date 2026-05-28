// compress/bc4.hlsl - Pure BC4 compression function
// No global state, no texture reads. Takes 16 scalar values, returns packed 64-bit block.
// BC4 format: 2x uint8 endpoints (16 bits) + 16x 3-bit indices (48 bits) = 64 bits
// When endpoint0 > endpoint1: 8-value interpolation mode

#ifndef COMPRESS_BC4_HLSL
#define COMPRESS_BC4_HLSL

// Compress a 4x4 block of single-channel values into BC4 (64-bit block as uint2)
// Layout:
//   .x bits [0..7]   = endpoint0 (uint8)
//   .x bits [8..15]  = endpoint1 (uint8)
//   .x bits [16..31] = first 16 bits of index data
//   .y bits [0..31]  = remaining 32 bits of index data
uint2 compress_bc4(float values[16]) {
    // Find min and max values
    float minVal = values[0];
    float maxVal = values[0];
    [unroll] for (int i = 1; i < 16; i++) {
        minVal = min(minVal, values[i]);
        maxVal = max(maxVal, values[i]);
    }

    // Quantize endpoints to 8 bits
    uint ep0 = (uint)(saturate(maxVal) * 255.0 + 0.5);
    uint ep1 = (uint)(saturate(minVal) * 255.0 + 0.5);

    // Ensure ep0 > ep1 for 8-value interpolation mode
    // If they are equal, nudge them apart
    if (ep0 == ep1) {
        if (ep0 < 255) {
            ep0 = ep0 + 1;
        } else {
            ep1 = ep1 - 1;
        }
    }

    // Generate 8-level palette (ep0 > ep1 triggers 8-value mode)
    float palette[8];
    float fep0 = (float)ep0 / 255.0;
    float fep1 = (float)ep1 / 255.0;
    palette[0] = fep0;
    palette[1] = fep1;
    palette[2] = (6.0 * fep0 + 1.0 * fep1) / 7.0;
    palette[3] = (5.0 * fep0 + 2.0 * fep1) / 7.0;
    palette[4] = (4.0 * fep0 + 3.0 * fep1) / 7.0;
    palette[5] = (3.0 * fep0 + 4.0 * fep1) / 7.0;
    palette[6] = (2.0 * fep0 + 5.0 * fep1) / 7.0;
    palette[7] = (1.0 * fep0 + 6.0 * fep1) / 7.0;

    // Assign each value to the closest palette entry (3-bit index)
    uint indices[16];
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
    }

    // Pack into 64 bits:
    // Byte 0: ep0, Byte 1: ep1, Bytes 2-7: 48 bits of 3-bit indices
    // Index stream: idx0 in bits[0..2], idx1 in bits[3..5], ...
    //
    // Final layout in uint2:
    // .x = ep0(8) | ep1(8) | indexStream_bits[0..15](16)
    // .y = indexStream_bits[16..47](32)

    // Build 48-bit index stream (16 indices x 3 bits)
    uint indexLow = 0;  // bits [0..31] of index stream
    uint indexHigh = 0; // bits [32..47] of index stream

    [unroll] for (int k = 0; k < 16; k++) {
        uint bitPos = (uint)k * 3;
        if (bitPos < 32) {
            indexLow |= (indices[k] << bitPos);
            // Handle case where 3-bit value straddles the 32-bit boundary
            if (bitPos > 29) {
                uint bitsInLow = 32 - bitPos;
                indexHigh |= (indices[k] >> bitsInLow);
            }
        } else {
            indexHigh |= (indices[k] << (bitPos - 32));
        }
    }

    // Pack final uint2
    uint packed_x = ep0 | (ep1 << 8) | ((indexLow & 0xFFFF) << 16);
    uint packed_y = (indexLow >> 16) | (indexHigh << 16);

    return uint2(packed_x, packed_y);
}

#endif // COMPRESS_BC4_HLSL
