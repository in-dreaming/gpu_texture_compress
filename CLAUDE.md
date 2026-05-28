# GPU Texture Compression SDK

## Project Overview

This project uses an **autoresearch** pattern to develop high-performance GPU texture
compression shaders. The final deliverable is `sdk/shaders/` — a standalone shader SDK.

## Architecture

```
sdk/shaders/       <- FINAL DELIVERABLE (agent optimizes these)
src/               <- Evaluation framework (DO NOT MODIFY during experiments)
experiments/       <- Autoresearch control (program.md, configs, results.tsv)
external/SDL/      <- SDL3 submodule (for GPU test harness)
```

## Build

```bash
cmake -B build -G Ninja
cmake --build build --config Release
```

## Run

```bash
# Print GPU info
build\Release\gtc_runner.exe --info

# Run experiment
build\Release\gtc_runner.exe --config experiments/configs/quick_bc1.json
```

## Shader Interface

All compression shaders in `sdk/shaders/` must conform to the interface defined
in `experiments/program.md`. Key bindings:
- `register(b0)`: CompressParams uniform buffer (32 bytes)
- `register(t0)` + `register(s0)`: Source texture + point sampler
- `register(u0)`: Output buffer (uint2 for 64-bit, uint4 for 128-bit formats)
- Entry point: `MainCS` with `[numthreads(8, 8, 1)]`

## Key Conventions

- Shaders are HLSL, compiled via SDL_shadercross to SPIRV/DXIL at runtime
- BC1/BC4 output 64-bit blocks (uint2); all others output 128-bit blocks (uint4)
- Each thread processes exactly one block
- `QualityLevel` 0/1/2 allows speed/quality tradeoff within same shader
