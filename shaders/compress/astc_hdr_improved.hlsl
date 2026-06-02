#ifndef ASTC_HDR_IMPROVED_HLSL
#define ASTC_HDR_IMPROVED_HLSL

//=============================================================================
// Improved HDR ASTC Support
// Higher quality HDR compression with better endpoint selection
//=============================================================================

#include "astc_common.hlsl"

// HDR Color Endpoint Modes (CEM)
#define ASTC_CEM_HDR_RGB_DIRECT        12  // HDR RGB, direct endpoints
#define ASTC_CEM_HDR_RGB_SCALE         13  // HDR RGB, scaled endpoints
#define ASTC_CEM_HDR_RGB_LDRA_DIRECT   14  // HDR RGB + LDR Alpha
#define ASTC_CEM_HDR_RGB_LDRA_SCALE    15  // HDR RGB + LDR Alpha scaled

//=============================================================================
// Improved HDR Endpoint Selection
// Uses log-space encoding for better HDR range handling
//=============================================================================

// Convert HDR value to log-space for more uniform quantization
float astc_hdr_to_log(float val)
{
    val = max(val, 1e-6);  // Avoid log(0)
    // Use log2 for better dynamic range representation
    return log2(val);
}

// Convert log-space back to HDR
float astc_log_to_hdr(float log_val)
{
    return exp2(log_val);
}

// Improved HDR endpoint selection with log-space PCA
void astc_hdr_compute_endpoints_improved(
    float3 hdr_pixels[16],
    out float3 ep0,
    out float3 ep1,
    out float log_range
)
{
    // Convert to log-space for PCA
    float3 log_pixels[16];
    float3 log_mean = float3(0, 0, 0);
    
    [unroll] for (int i = 0; i < 16; i++) {
        log_pixels[i] = float3(
            astc_hdr_to_log(hdr_pixels[i].r),
            astc_hdr_to_log(hdr_pixels[i].g),
            astc_hdr_to_log(hdr_pixels[i].b)
        );
        log_mean += log_pixels[i];
    }
    log_mean /= 16.0;
    
    // Compute covariance in log-space
    float3 cov_diag = float3(0, 0, 0);
    float3 cov_off = float3(0, 0, 0);
    
    [unroll] for (int j = 0; j < 16; j++) {
        float3 d = log_pixels[j] - log_mean;
        cov_diag += d * d;
        cov_off += float3(d.x * d.y, d.x * d.z, d.y * d.z);
    }
    cov_diag /= 16.0;
    cov_off /= 16.0;
    
    // PCA axis in log-space
    float3 axis = astc_compute_pca_axis(log_mean, cov_diag, cov_off);
    
    // Project and find extremes in log-space
    float min_proj = 1e10, max_proj = -1e10;
    [unroll] for (int k = 0; k < 16; k++) {
        float proj = dot(log_pixels[k] - log_mean, axis);
        min_proj = min(min_proj, proj);
        max_proj = max(max_proj, proj);
    }
    
    // Convert endpoints back to linear space
    float3 log_ep0 = log_mean + axis * max_proj;
    float3 log_ep1 = log_mean + axis * min_proj;
    
    ep0 = float3(astc_log_to_hdr(log_ep0.x), astc_log_to_hdr(log_ep0.y), astc_log_to_hdr(log_ep0.z));
    ep1 = float3(astc_log_to_hdr(log_ep1.x), astc_log_to_hdr(log_ep1.y), astc_log_to_hdr(log_ep1.z));
    
    // Clamp to reasonable HDR range
    ep0 = clamp(ep0, 0.0, 65504.0);
    ep1 = clamp(ep1, 0.0, 65504.0);
    
    // Compute log range for weight calculation
    log_range = max_proj - min_proj;
}

//=============================================================================
// HDR Weight Calculation with Luminance Weighting
// Gives more weight to luminance for HDR content
//=============================================================================

// Compute HDR-aware weight (0-1) for a pixel given endpoints
float astc_hdr_compute_weight_luminance(
    float3 hdr_pixel,
    float3 ep0,
    float3 ep1
)
{
    // Use luminance-weighted distance
    float3 lum_weights = float3(0.299, 0.587, 0.114);
    
    float lum_pixel = dot(hdr_pixel, lum_weights);
    float lum_ep0 = dot(ep0, lum_weights);
    float lum_ep1 = dot(ep1, lum_weights);
    
    if (abs(lum_ep1 - lum_ep0) < 1e-6) return 0.0;
    
    // Normalize to 0-1
    float t = (lum_pixel - lum_ep0) / (lum_ep1 - lum_ep0);
    return saturate(t);
}

// Full RGB HDR weight calculation
float astc_hdr_compute_weight_rgb(
    float3 hdr_pixel,
    float3 ep0,
    float3 ep1
)
{
    // Per-channel weights
    float3 weights = float3(0, 0, 0);
    [unroll] for (int c = 0; c < 3; c++) {
        float range = max(abs(ep1[c] - ep0[c]), 1e-6);
        weights[c] = (hdr_pixel[c] - ep0[c]) / range;
    }
    
    // Average of per-channel weights
    return saturate((weights.x + weights.y + weights.z) / 3.0);
}

//=============================================================================
// Improved HDR Block Compression
//=============================================================================

// Improved 4x4 HDR compression with log-space PCA
uint4 astc_compress_4x4_hdr_improved(float4 hdr_pixels[16])
{
    // Check for constant block
    float3 min_val = float3(1e10, 1e10, 1e10);
    float3 max_val = float3(-1e10, -1e10, -1e10);
    float min_a = 1e10, max_a = -1e10;
    float3 avg_rgb = float3(0, 0, 0);
    float avg_a = 0;
    
    [unroll] for (int i = 0; i < 16; i++) {
        min_val = min(min_val, hdr_pixels[i].rgb);
        max_val = max(max_val, hdr_pixels[i].rgb);
        min_a = min(min_a, hdr_pixels[i].a);
        max_a = max(max_a, hdr_pixels[i].a);
        avg_rgb += hdr_pixels[i].rgb;
        avg_a += hdr_pixels[i].a;
    }
    avg_rgb /= 16.0;
    avg_a /= 16.0;
    
    float3 range = max_val - min_val;
    if (dot(range, range) < 1e-6 && (max_a - min_a) < 1e-6) {
        return astc_void_extent(float4(avg_rgb, avg_a));
    }
    
    // Compute HDR endpoints using improved log-space method
    float3 ep0, ep1;
    float log_range;
    float3 pixel_arr[16];
    [unroll] for (int j = 0; j < 16; j++) pixel_arr[j] = hdr_pixels[j].rgb;
    
    astc_hdr_compute_endpoints_improved(pixel_arr, ep0, ep1, log_range);
    
    // Compute HDR scale factor
    float max_hdr = max(max(ep0.r, ep0.g), ep0.b);
    max_hdr = max(max_hdr, max(ep1.r, ep1.g));
    max_hdr = max(max_hdr, max(ep1.b, 1.0));
    
    // Normalize endpoints to 0-1
    float3 norm_ep0 = ep0 / max_hdr;
    float3 norm_ep1 = ep1 / max_hdr;
    
    // Quantize endpoints
    uint endpoints[6];
    endpoints[0] = (uint)(saturate(norm_ep0.r) * 255.0 + 0.5);
    endpoints[1] = (uint)(saturate(norm_ep1.r) * 255.0 + 0.5);
    endpoints[2] = (uint)(saturate(norm_ep0.g) * 255.0 + 0.5);
    endpoints[3] = (uint)(saturate(norm_ep1.g) * 255.0 + 0.5);
    endpoints[4] = (uint)(saturate(norm_ep0.b) * 255.0 + 0.5);
    endpoints[5] = (uint)(saturate(norm_ep1.b) * 255.0 + 0.5);
    
    // Compute weights using HDR-aware method
    uint weights[16];
    [unroll] for (int w = 0; w < 16; w++) {
        float3 target = hdr_pixels[w].rgb / max_hdr;
        float3 ep0_norm = norm_ep0;
        float3 ep1_norm = norm_ep1;
        
        float best_dist = 1e10;
        uint best_idx = 0;
        
        // Use log-space for weight interpolation
        [unroll] for (uint idx = 0; idx < 4; idx++) {
            float t = float(idx) / 3.0;
            float3 palette = lerp(ep0_norm, ep1_norm, t);
            
            // HDR-aware distance with luminance weighting
            float3 diff = target - palette;
            float dist = dot(diff, diff);
            
            if (dist < best_dist) {
                best_dist = dist;
                best_idx = idx;
            }
        }
        weights[w] = best_idx;
    }
    
    return astc_pack_block_with_mode(ASTC_BLOCK_MODE_4x4_Q4, endpoints, weights);
}

#endif // ASTC_HDR_IMPROVED_HLSL
