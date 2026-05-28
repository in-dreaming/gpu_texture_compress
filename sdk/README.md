# GPU Texture Compression Shader SDK

A collection of GPU compute/fragment shader functions for real-time texture compression, supporting ASTC and BCn full formats.

## Supported Formats

| Format | Block | bpp | Output | Use Case |
|--------|-------|-----|--------|----------|
| BC1 | 4×4 | 4.00 | uint2 | RGB color (opaque) |
| BC3 | 4×4 | 8.00 | uint4 | RGBA (independent alpha) |
| BC4 | 4×4 | 4.00 | uint2 | Single channel (AO, roughness) |
| BC5 | 4×4 | 8.00 | uint4 | Two channels (normal maps XY) |
| BC6H | 4×4 | 8.00 | uint4 | HDR RGB |
| BC7 | 4×4 | 8.00 | uint4 | RGBA (high quality) |
| ASTC 4×4 | 4×4 | 8.00 | uint4 | Mobile/universal |
| ASTC 5×4 | 5×4 | 6.40 | uint4 | Mobile/universal |
| ASTC 5×5 | 5×5 | 5.12 | uint4 | Mobile/universal |
| ASTC 6×5 | 6×5 | 4.27 | uint4 | Mobile/universal |
| ASTC 6×6 | 6×6 | 3.56 | uint4 | Mobile/universal |
| ASTC 8×5 | 8×5 | 3.20 | uint4 | Mobile/universal |
| ASTC 8×6 | 8×6 | 2.67 | uint4 | Mobile/universal |
| ASTC 8×8 | 8×8 | 2.00 | uint4 | Mobile/universal |
| ASTC 10×5 | 10×5 | 2.56 | uint4 | Mobile/universal |
| ASTC 10×6 | 10×6 | 2.13 | uint4 | Mobile/universal |
| ASTC 10×8 | 10×8 | 1.60 | uint4 | Mobile/universal |
| ASTC 10×10 | 10×10 | 1.28 | uint4 | Mobile/universal |
| ASTC 12×10 | 12×10 | 1.07 | uint4 | Mobile/universal |
| ASTC 12×12 | 12×12 | 0.89 | uint4 | Mobile/universal |

## Directory Structure

```
sdk/shaders/
├── common/                     Shared utilities
│   ├── gtc_interface.hlsl      Uniform buffer + texture binding interface
│   ├── color_space.hlsl        sRGB/linear/YCoCg conversions
│   └── endpoint_fit.hlsl       PCA / least-squares endpoint fitting
├── compress/                   Pure algorithm functions (no dispatch)
│   ├── bc1.hlsl ... bc7.hlsl  BCn compression functions
│   ├── astc_common.hlsl        ASTC shared utilities
│   └── astc_4x4.hlsl ... astc_12x12.hlsl  Per-size ASTC functions
└── dispatch/                   Compute shader entry points ([numthreads])
    ├── bc1_cs.hlsl ... bc7_cs.hlsl
    └── astc_4x4_cs.hlsl ... astc_12x12_cs.hlsl
```

## Usage

### In a Compute Shader (Direct Dispatch)

Compile a dispatch shader (e.g., `dispatch/bc1_cs.hlsl`) and dispatch it:

```
Bindings:
  Set 0, Binding 0: Combined image/sampler (source texture)
  Set 1, Binding 0: RW storage buffer (output blocks)
  Set 2, Binding 0: Uniform buffer (CompressParams, 32 bytes)

Uniform buffer layout (32 bytes):
  int32  TexWidth       // Source texture width in pixels
  int32  TexHeight      // Source texture height in pixels
  int32  BlocksX        // Number of blocks horizontally
  int32  BlocksY        // Number of blocks vertically
  int32  QualityLevel   // 0=fast, 1=balanced, 2=best
  int32  Flags          // bit0: NORMALMAP, bit1: HAS_ALPHA, bit2: SRGB
  float  Pad0           // Padding
  float  Pad1           // Padding

Dispatch: ceil(BlocksX/8) x ceil(BlocksY/8) x 1
Each thread processes one block.
```

### In a Fragment Shader (Include as Library)

```hlsl
// In your fragment shader:
#include "compress/bc1.hlsl"

// Load your 4x4 pixel block however you want
float3 pixels[16] = LoadMyBlock(uv);

// Call the pure compression function
uint2 compressed = compress_bc1(pixels);

// Write to your output however you want
outputBuffer[blockIndex] = compressed;
```

### Compile with DXC (HLSL to SPIRV)

```bash
dxc -T cs_6_0 -E MainCS -spirv -fspv-target-env=vulkan1.1 \
    -fvk-bind-register t0 0 0 0 \
    -fvk-bind-register s0 0 0 0 \
    -fvk-bind-register u0 0 0 1 \
    -fvk-bind-register b0 0 0 2 \
    -I sdk/shaders/ \
    -Fo output.spv \
    sdk/shaders/dispatch/bc1_cs.hlsl
```

## Function Signatures

```hlsl
// BCn (4x4 blocks, 16 pixels)
uint2 compress_bc1(float3 pixels[16]);     // RGB → 64-bit
uint4 compress_bc3(float4 pixels[16]);     // RGBA → 128-bit
uint2 compress_bc4(float values[16]);      // R → 64-bit
uint4 compress_bc5(float2 pixels[16]);     // RG → 128-bit
uint4 compress_bc6h(float3 pixels[16]);    // HDR RGB → 128-bit
uint4 compress_bc7(float4 pixels[16]);     // RGBA → 128-bit

// ASTC (variable block size)
uint4 compress_astc_4x4(float4 pixels[16]);
uint4 compress_astc_5x4(float4 pixels[20]);
uint4 compress_astc_5x5(float4 pixels[25]);
uint4 compress_astc_6x5(float4 pixels[30]);
uint4 compress_astc_6x6(float4 pixels[36]);
uint4 compress_astc_8x5(float4 pixels[40]);
uint4 compress_astc_8x6(float4 pixels[48]);
uint4 compress_astc_8x8(float4 pixels[64]);
uint4 compress_astc_10x5(float4 pixels[50]);
uint4 compress_astc_10x6(float4 pixels[60]);
uint4 compress_astc_10x8(float4 pixels[80]);
uint4 compress_astc_10x10(float4 pixels[100]);
uint4 compress_astc_12x10(float4 pixels[120]);
uint4 compress_astc_12x12(float4 pixels[144]);
```

## Pixel Layout

All functions expect pixels in **row-major order** (left-to-right, top-to-bottom):
```
pixels[0]  = (0,0)  pixels[1]  = (1,0)  ...  pixels[W-1]   = (W-1,0)
pixels[W]  = (0,1)  pixels[W+1] = (1,1) ...  pixels[2W-1]  = (W-1,1)
...
```

## License

MIT
