// endpoint_fit.hlsl - Endpoint fitting utilities (PCA, least squares)
// Part of GPU Texture Compression SDK

#ifndef ENDPOINT_FIT_HLSL
#define ENDPOINT_FIT_HLSL

// Compute PCA axis from a set of pixels using power iteration
// pixels: array of float3 colors (16 for 4x4 block)
// mean: precomputed mean of pixels
// Returns: normalized principal axis direction
float3 ComputePCAAxis(float3 pixels[16], float3 mean) {
    // Compute covariance matrix (symmetric 3x3)
    float cov[6] = {0, 0, 0, 0, 0, 0}; // xx, xy, xz, yy, yz, zz

    [unroll]
    for (int i = 0; i < 16; i++) {
        float3 d = pixels[i] - mean;
        cov[0] += d.x * d.x;
        cov[1] += d.x * d.y;
        cov[2] += d.x * d.z;
        cov[3] += d.y * d.y;
        cov[4] += d.y * d.z;
        cov[5] += d.z * d.z;
    }

    // Power iteration to find dominant eigenvector
    float3 axis = float3(0.26726, 0.80178, 0.53452); // Initial guess (golden ratio-ish)

    [unroll]
    for (int iter = 0; iter < 8; iter++) {
        float3 new_axis;
        new_axis.x = cov[0] * axis.x + cov[1] * axis.y + cov[2] * axis.z;
        new_axis.y = cov[1] * axis.x + cov[3] * axis.y + cov[4] * axis.z;
        new_axis.z = cov[2] * axis.x + cov[4] * axis.y + cov[5] * axis.z;

        float len = length(new_axis);
        if (len < 0.00001) {
            // Degenerate case: all pixels are the same color
            return float3(1, 0, 0);
        }
        axis = new_axis / len;
    }

    return axis;
}

// Compute PCA axis for a variable-size block (up to 64 pixels)
float3 ComputePCAAxisN(float3 pixels[64], int count, float3 mean) {
    float cov[6] = {0, 0, 0, 0, 0, 0};

    for (int i = 0; i < count; i++) {
        float3 d = pixels[i] - mean;
        cov[0] += d.x * d.x;
        cov[1] += d.x * d.y;
        cov[2] += d.x * d.z;
        cov[3] += d.y * d.y;
        cov[4] += d.y * d.z;
        cov[5] += d.z * d.z;
    }

    float3 axis = float3(0.26726, 0.80178, 0.53452);

    [unroll]
    for (int iter = 0; iter < 8; iter++) {
        float3 new_axis;
        new_axis.x = cov[0] * axis.x + cov[1] * axis.y + cov[2] * axis.z;
        new_axis.y = cov[1] * axis.x + cov[3] * axis.y + cov[4] * axis.z;
        new_axis.z = cov[2] * axis.x + cov[4] * axis.y + cov[5] * axis.z;

        float len = length(new_axis);
        if (len < 0.00001) return float3(1, 0, 0);
        axis = new_axis / len;
    }

    return axis;
}

// Project all pixels onto axis, return min/max projections
void ProjectOntoAxis(float3 pixels[16], float3 mean, float3 axis,
                     out float minProj, out float maxProj) {
    minProj = 1e10;
    maxProj = -1e10;

    [unroll]
    for (int i = 0; i < 16; i++) {
        float proj = dot(pixels[i] - mean, axis);
        minProj = min(minProj, proj);
        maxProj = max(maxProj, proj);
    }
}

// Refine endpoints using least-squares (one iteration)
// Given current endpoints and assignments, compute optimal endpoints
void RefineEndpointsLeastSquares(float3 pixels[16], uint indices, int num_colors,
                                 inout float3 endpoint0, inout float3 endpoint1) {
    // Accumulate per-endpoint weighted sums
    float3 sum0 = 0, sum1 = 0;
    float weight0 = 0, weight1 = 0;

    float inv_steps = 1.0 / (float)(num_colors - 1);

    [unroll]
    for (int i = 0; i < 16; i++) {
        uint idx = (indices >> (i * 2)) & 0x3;
        float t = (float)idx * inv_steps; // 0..1 interpolation parameter

        // Weight toward endpoint 0 or endpoint 1
        sum0 += pixels[i] * (1.0 - t);
        sum1 += pixels[i] * t;
        weight0 += (1.0 - t) * (1.0 - t);
        weight1 += t * t;
    }

    if (weight0 > 0.001) endpoint0 = sum0 / weight0;
    if (weight1 > 0.001) endpoint1 = sum1 / weight1;
}

#endif // ENDPOINT_FIT_HLSL
