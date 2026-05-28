// gtc_interface.hlsl - Standard shader interface for GPU Texture Compression SDK
// All compression shaders must include this file.
// DO NOT MODIFY during autoresearch experiments.

#ifndef GTC_INTERFACE_HLSL
#define GTC_INTERFACE_HLSL

// Uniform buffer (SDL3 GPU pushes this via SDL_PushGPUComputeUniformData)
// DXC compiles this to a UBO at binding 2 (after sampler@0 + storage_buffer@1)
cbuffer GtcParams : register(b0) {
    int TexWidth;
    int TexHeight;
    int BlocksX;
    int BlocksY;
    int QualityLevel;
    int Flags;
    float Pad0;
    float Pad1;
};

// Flag bits
#define GTC_FLAG_NORMALMAP  (1 << 0)
#define GTC_FLAG_HAS_ALPHA  (1 << 1)
#define GTC_FLAG_SRGB       (1 << 2)

// Source texture + sampler (binding 0 as combined image/sampler)
Texture2D<float4> SourceTexture : register(t0);
SamplerState PointSampler : register(s0);

#endif // GTC_INTERFACE_HLSL
