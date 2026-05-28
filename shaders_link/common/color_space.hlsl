// color_space.hlsl - Color space conversion utilities
// Part of GPU Texture Compression SDK

#ifndef COLOR_SPACE_HLSL
#define COLOR_SPACE_HLSL

// sRGB to linear conversion
float3 SRGBToLinear(float3 srgb) {
    // Exact sRGB EOTF
    float3 lo = srgb / 12.92;
    float3 hi = pow((srgb + 0.055) / 1.055, 2.4);
    return select(srgb <= 0.04045, lo, hi);
}

// Linear to sRGB conversion
float3 LinearToSRGB(float3 linear_col) {
    float3 lo = linear_col * 12.92;
    float3 hi = 1.055 * pow(linear_col, 1.0 / 2.4) - 0.055;
    return select(linear_col <= 0.0031308, lo, hi);
}

// RGB to YCoCg conversion (lossless color space for better compression)
float3 RGBToYCoCg(float3 rgb) {
    float Y  =  0.25 * rgb.r + 0.5 * rgb.g + 0.25 * rgb.b;
    float Co =  0.5  * rgb.r - 0.5 * rgb.b;
    float Cg = -0.25 * rgb.r + 0.5 * rgb.g - 0.25 * rgb.b;
    return float3(Y, Co, Cg);
}

// YCoCg to RGB conversion
float3 YCoCgToRGB(float3 ycocg) {
    float Y  = ycocg.x;
    float Co = ycocg.y;
    float Cg = ycocg.z;
    float r = Y + Co - Cg;
    float g = Y + Cg;
    float b = Y - Co - Cg;
    return float3(r, g, b);
}

// Perceptual luminance weight
float Luminance(float3 rgb) {
    return dot(rgb, float3(0.2126, 0.7152, 0.0722));
}

// Perceptual color distance (weighted by human vision sensitivity)
float PerceptualDistance(float3 a, float3 b) {
    float3 diff = a - b;
    // Weight green more heavily (human eye is most sensitive)
    return dot(diff * diff, float3(0.2126, 0.7152, 0.0722));
}

#endif // COLOR_SPACE_HLSL
