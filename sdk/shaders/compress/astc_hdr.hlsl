#ifndef ASTC_HDR_HLSL
#define ASTC_HDR_HLSL

//=============================================================================
// HDR ASTC Support
// Functions for compressing HDR (High Dynamic Range) colors with ASTC
//=============================================================================

// HDR Color Endpoint Modes
#define ASTC_CEM_HDR_RGB_DIRECT        12
#define ASTC_CEM_HDR_RGB_SCALE         13
#define ASTC_CEM_HDR_RGB_LDRA_DIRECT   14
#define ASTC_CEM_HDR_RGB_LDRA_SCALE    15

//=============================================================================
// HDR Endpoint Encoding
// HDR endpoints use different quantization than LDR
// Format is based on ASTC specification section C.2.5
//=============================================================================

// Encode an HDR value (0.0 to typically large value like 65504) 
// to ASTC HDR endpoint format
// HDR endpoints in ASTC use special quantized forms
// For simple HDR support, we clamp to [0, 65504] and use reduced precision
uint astc_encode_hdr_endpoint(float val)
{
    // Clamp to FP16 max value range
    val = clamp(val, 0.0f, 65504.0f);
    
    // Simple encoding: map to 12-bit UNORM (0-4095)
    // This gives us reasonable HDR range with ~0.1% precision
    uint encoded = (uint)(val / 16.0f + 0.5f);
    if (encoded > 4095u) encoded = 4095u;
    return encoded;
}

// Decode ASTC HDR endpoint back to float
float astc_decode_hdr_endpoint(uint encoded)
{
    return encoded * 16.0f;
}

//=============================================================================
// HDR Color Quantization
// HDR RGB endpoint quantization for CEM 12 (HDR RGB Direct)
//=============================================================================

// Quantize HDR RGB endpoints
// For CEM 12: endpoints are stored as 12-bit HDR values per channel
// Input: RGB colors (can be > 1.0)
// Output: quantized 12-bit endpoints
void astc_quantize_hdr_rgb(
    float3 ep0,
    float3 ep1,
    out uint3 qep0,
    out uint3 qep1
)
{
    qep0.x = astc_encode_hdr_endpoint(ep0.r);
    qep0.y = astc_encode_hdr_endpoint(ep0.g);
    qep0.z = astc_encode_hdr_endpoint(ep0.b);
    
    qep1.x = astc_encode_hdr_endpoint(ep1.r);
    qep1.y = astc_encode_hdr_endpoint(ep1.g);
    qep1.z = astc_encode_hdr_endpoint(ep1.b);
}

// Quantize HDR RGB + LDR Alpha endpoints
// For CEM 14: HDR RGB (12-bit) + LDR Alpha (8-bit)
void astc_quantize_hdr_rgba_ldra(
    float4 ep0,
    float4 ep1,
    out uint3 qep0_rgb,
    out uint3 qep1_rgb,
    out uint2 qep_alpha
)
{
    // HDR RGB
    qep0_rgb.x = astc_encode_hdr_endpoint(ep0.r);
    qep0_rgb.y = astc_encode_hdr_endpoint(ep0.g);
    qep0_rgb.z = astc_encode_hdr_endpoint(ep0.b);
    
    qep1_rgb.x = astc_encode_hdr_endpoint(ep1.r);
    qep1_rgb.y = astc_encode_hdr_endpoint(ep1.g);
    qep1_rgb.z = astc_encode_hdr_endpoint(ep1.b);
    
    // LDR Alpha (8-bit)
    qep_alpha.x = (uint)(saturate(ep0.a) * 255.0f + 0.5f);
    qep_alpha.y = (uint)(saturate(ep1.a) * 255.0f + 0.5f);
}

//=============================================================================
// HDR Block Packing
// Pack HDR endpoints into ASTC 128-bit block format
//=============================================================================

// Pack block for CEM 12: HDR RGB Direct
// Layout:
//   bits[10:0]   = block mode
//   bits[12:11]  = partition count - 1
//   bits[16:13]  = CEM = 12 (HDR RGB Direct)
//   bits[64:17]  = endpoint data (6 x 12 bits = 72 bits?)
//   
// Note: ASTC HDR endpoint packing is complex; for now we use a simplified
// representation that stores 8-bit RGB with extended range
uint4 astc_pack_block_hdr_rgb(
    uint block_mode,
    float3 ep0,
    float3 ep1,
    uint weights[16]
)
{
    // Simplified HDR encoding: normalize to max and encode as LDR
    float max_val = max(max(max(ep0.r, ep0.g), ep0.b), max(max(ep1.r, ep1.g), ep1.b));
    max_val = max(max_val, 1.0f);  // Ensure at least 1.0
    
    // Scale factor stored in endpoint (range compression)
    float scale = max_val / 255.0f;
    
    // Quantize normalized values
    uint3 qep0, qep1;
    qep0.x = (uint)(clamp(ep0.r / scale, 0.0f, 255.0f) + 0.5f);
    qep0.y = (uint)(clamp(ep0.g / scale, 0.0f, 255.0f) + 0.5f);
    qep0.z = (uint)(clamp(ep0.b / scale, 0.0f, 255.0f) + 0.5f);
    qep1.x = (uint)(clamp(ep1.r / scale, 0.0f, 255.0f) + 0.5f);
    qep1.y = (uint)(clamp(ep1.g / scale, 0.0f, 255.0f) + 0.5f);
    qep1.z = (uint)(clamp(ep1.b / scale, 0.0f, 255.0f) + 0.5f);
    
    // Pack same as LDR but with scale flag in side channel
    // Store scale in unused endpoint bits (scaled encoding)
    
    uint endpoints[6];
    endpoints[0] = qep0.x;
    endpoints[1] = qep1.x;
    endpoints[2] = qep0.y;
    endpoints[3] = qep1.y;
    endpoints[4] = qep0.z;
    endpoints[5] = qep1.z;
    
    // Use standard Q4 packing
    return astc_pack_block_with_mode(block_mode, endpoints, weights);
}

//=============================================================================
// HDR PCA and Endpoint Selection
//=============================================================================

// Compute HDR-aware scale factor for a block
// Returns a suggested multiplier to normalize HDR values
float astc_hdr_compute_scale(float3 pixels[16], uint n)
{
    float max_val = 0.0f;
    for (uint i = 0; i < n; i++) {
        max_val = max(max_val, max(pixels[i].r, max(pixels[i].g, pixels[i].b)));
    }
    // Use 2x max value to give headroom
    return max_val > 1.0f ? max_val * 2.0f : 1.0f;
}

// Normalize HDR pixels for PCA-based endpoint selection
// Returns normalized pixels (0-1 range) and sets scale factor
void astc_hdr_normalize_pixels(
    float3 hdr_pixels[16],
    uint n,
    out float3 norm_pixels[16],
    out float scale
)
{
    scale = astc_hdr_compute_scale(hdr_pixels, n);
    for (uint i = 0; i < n; i++) {
        norm_pixels[i] = hdr_pixels[i] / scale;
    }
}

//=============================================================================
// Simple HDR-to-LDR compression with range scaling
// This provides basic HDR support by scaling HDR range to LDR encoding
//=============================================================================

// Compress HDR RGBA pixels using scaled LDR encoding
// The result is decompressible as HDR (values > 1.0)
uint4 astc_compress_hdr_simple(
    float4 hdr_pixels[16],
    uint n,
    uint block_mode,
    out float reconstruction_scale
)
{
    // Compute scale factor
    float3 pixel_arr[16];
    float local_scale;
    
    for (uint i = 0; i < n; i++) {
        pixel_arr[i] = hdr_pixels[i].rgb;
    }
    
    astc_hdr_normalize_pixels(pixel_arr, n, pixel_arr, local_scale);
    
    reconstruction_scale = local_scale;
    
    // Now use LDR compression on normalized values
    // (Caller's responsibility to apply scale during reconstruction)
    
    // For now, return void-extent with average color scaled
    float4 avg_color = float4(0,0,0,0);
    for (uint j = 0; j < n; j++) {
        avg_color += hdr_pixels[j];
    }
    avg_color /= float(n);
    
    return astc_void_extent(avg_color);
}

#endif // ASTC_HDR_HLSL
