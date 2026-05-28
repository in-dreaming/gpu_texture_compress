# GPU Texture Compression — Autoresearch Program

## Overview

You are an autonomous researcher optimizing GPU texture compression shaders.
Your goal: **maximize compression quality (PSNR, SSIM) while keeping GPU
compression time under the budget.**

The final deliverable is a set of shader files in `sdk/shaders/` that form a
standalone Shader SDK — independent of any specific engine or graphics API.

## Per-Format Research Programs

Each format has its own detailed program with specific strategies:
- `experiments/programs/bc1.md` — BC1 (RGB 4bpp)
- `experiments/programs/bc3.md` — BC3 (RGBA 8bpp = BC1+BC4)
- `experiments/programs/bc4.md` — BC4 (R 4bpp, single channel)
- `experiments/programs/bc5.md` — BC5 (RG 8bpp = 2×BC4, normal maps)
- `experiments/programs/bc6h.md` — BC6H (HDR RGB 8bpp, 14 modes)
- `experiments/programs/bc7.md` — BC7 (RGBA 8bpp, 8 modes)
- `experiments/programs/astc.md` — ASTC (14 block sizes, 0.89-8.00 bpp)

**Read the relevant program file before starting work on that format.**

## Reference Source Code (deps/)

| Directory | Description | Key Files |
|-----------|-------------|-----------|
| `deps/astc_encoder/` | GPU ASTC 4x4/6x6 (D3D11 compute shader) | `ASTC_Encode.hlsl`, `ASTC_Table.hlsl`, `ASTC_IntegerSequenceEncoding.hlsl` |
| `deps/astc-encoder/` | ARM official ASTC encoder (CPU, all modes) | `Source/astcenc_compress_symbolic.cpp` |
| `deps/DirectXTex/` | Microsoft BCn reference (CPU) | `DirectXTexCompressBC.cpp`, `BC7Encode.cpp`, `BC6HEncode.cpp` |

## Working Directory

Project root: the git repository root.

## Build & Run

```bash
# Build
cmake --build build --config Release

# Run a quick experiment (BC1 format, 3 test textures)
build\src\Release\gtc_runner.exe --config experiments/configs/quick_bc1.json

# Run full evaluation (all formats)
build\src\Release\gtc_runner.exe --config experiments/configs/full_sweep.json
```

## What You CAN Modify

Only files under `sdk/shaders/`:
- `sdk/shaders/compress/bc1.hlsl` — BC1 encoder function
- `sdk/shaders/compress/bc3.hlsl` — BC3 encoder function
- `sdk/shaders/compress/bc4.hlsl` — BC4 encoder function
- `sdk/shaders/compress/bc5.hlsl` — BC5 encoder function
- `sdk/shaders/compress/bc6h.hlsl` — BC6H encoder function (HDR)
- `sdk/shaders/compress/bc7.hlsl` — BC7 encoder function
- `sdk/shaders/compress/astc.hlsl` — ASTC encoder function (all 14 block sizes)
- `sdk/shaders/dispatch/*_cs.hlsl` — Compute shader dispatch entries
- `sdk/shaders/common/*.hlsl` — Shared utilities

## What You CANNOT Modify

- `src/**` — Framework code (fixed evaluation harness)
- `shaders/infrastructure/**` — Fixed decompressors
- `experiments/program.md` — This file
- `include/**` — Shared type definitions
- `experiments/configs/**` — Experiment configurations

## Shader Interface Contract

Compression algorithm files (`sdk/shaders/compress/*.hlsl`) export pure functions:
```hlsl
uint2 compress_bc1(float3 pixels[16]);   // 64-bit block
uint4 compress_bc7(float4 pixels[16]);   // 128-bit block
uint4 compress_astc(float4 pixels[N], uint pixel_count); // 128-bit block
```

Dispatch files (`sdk/shaders/dispatch/*_cs.hlsl`) include the interface and call the function:
```hlsl
#include "common/gtc_interface.hlsl"  // provides TexWidth,BlocksX,SourceTexture etc.
#include "compress/bc1.hlsl"
RWStructuredBuffer<uint2> OutputBlocks : register(u0);
[numthreads(8, 8, 1)]
void MainCS(uint3 DTid : SV_DispatchThreadID) { ... }
```

Texture2D<float4> SourceTexture : register(t0);
SamplerState PointSampler : register(s0);
RWStructuredBuffer<uint2> OutputBlocks : register(u0);  // uint2 for 64-bit formats (BC1, BC4)
// or: RWStructuredBuffer<uint4> OutputBlocks : register(u0);  // uint4 for 128-bit formats

[numthreads(8, 8, 1)]
void MainCS(uint3 DTid : SV_DispatchThreadID) { ... }
```

## Metrics (Goal: optimize these)

| Metric | Direction | Description |
|--------|-----------|-------------|
| avg_psnr | Higher = better | Peak Signal-to-Noise Ratio (dB) |
| avg_ssim | Higher = better | Structural Similarity Index |
| avg_flip | Lower = better | NVIDIA FLIP perceptual difference |
| avg_time_ms | Lower = better | GPU compression time |

**Primary target**: avg_psnr (maximize)
**Constraint**: avg_time_ms must stay under 10ms for 1K textures

## Output Format

The runner prints results in this format:
```
---
format:          BC1
avg_psnr:        34.5678
avg_ssim:        0.9654
avg_flip:        0.0412
avg_lpips:       0.0523
avg_time_ms:     0.92
num_textures:    3
---
```

Extract key metrics: `findstr "avg_psnr" run.log`

## Experiment Loop

LOOP FOREVER:

1. Pick a format/shader to optimize (or optimize shared utilities)
2. Modify the shader(s) in `sdk/shaders/`
3. Commit: `git add sdk/shaders/ && git commit -m "brief description"`
4. Build: `cmake --build build --config Release 2>build_err.log`
   - If build fails: `type build_err.log` (look for shader compilation errors)
5. Run: `build\src\Release\gtc_runner.exe --config experiments/configs/quick_bc1.json > run.log 2>&1`
6. Check results: `findstr "avg_psnr avg_ssim avg_flip avg_time_ms" run.log`
7. If metrics improved → keep (advance branch)
8. If metrics worse or crash → discard (`git reset --hard HEAD~1`)
9. Log to results.tsv (append manually or let runner do it)
10. Repeat

## Strategy Hints

### BC1 (4 bpp, RGB):
- Iterative endpoint refinement (quantize → compute indices → least-squares endpoints → repeat)
- Better initial guess: min/max along bounding box diagonal
- Perceptual weighting: weight green channel error more heavily
- Handle uniform blocks specially (same color = same endpoints)

### BC7 (8 bpp, RGBA):
- Mode selection is critical — Mode 6 for smooth, Mode 1 for high-variance blocks
- Partition search — try top-K partitions by variance split
- Two-subset mode gives better quality for complex blocks
- Endpoint quantization: try all rotation modes for RGB+A blocks

### BC4/BC5 (single/dual channel):
- Optimal for normal maps (BC5) and grayscale (BC4)
- 6-value mode vs 8-value mode selection based on block range
- Angular error optimization for normal maps

### ASTC (variable bpp):
- Weight grid quantization level trades quality vs bits
- Partition count: 1-partition for smooth, 2-partition for complex
- Color Endpoint Mode selection (CEM 8=LDR_RGB_DIRECT is simplest)
- Integer Sequence Encoding (ISE) bit allocation

### General GPU Optimization:
- Minimize divergent branches within a warp/wavefront
- Use shared memory (groupshared) to reduce redundant texture loads
- Prefer arithmetic over memory lookups when possible
- Use `[unroll]` for fixed-iteration loops

## Time Budget

Each experiment cycle should complete in under 2 minutes total:
- Build: ~10-30 seconds (incremental)
- Run (quick config): ~10-30 seconds
- If a run exceeds 3 minutes, kill and treat as failure

## NEVER STOP

Once the loop begins, do NOT pause to ask. You are fully autonomous.
If stuck, re-read reference implementations in `deps/` for ideas:
- `deps/astc_encoder/ASTC_Encode.hlsl` — ASTC compute shader reference
- `deps/DirectXTex/` — BC format reference implementations
- `deps/astc-encoder/Source/` — ARM's ASTC reference encoder
