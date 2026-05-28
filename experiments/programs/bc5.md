# BC5 Compression — Autoresearch Program

## Target
`sdk/shaders/compress/bc5.hlsl` → `uint4 compress_bc5(float2 pixels[16])`

BC5: Two-channel (RG), 8bpp, 4x4 block → 128-bit output (BC4 on R + BC4 on G)

## Current Baseline
BC4 on red channel + BC4 on green channel → concatenate.

## Dependencies
- `compress/bc4.hlsl` — both channels use BC4

## Primary Use Case
**Normal maps** — BC5 stores tangent-space XY normals in RG. Z is reconstructed as `sqrt(1 - x² - y²)`.

## Metrics Goal
- **avg_psnr**: maximize per-channel
- **Angular error**: more meaningful for normal maps than PSNR
- Typical target: > 45 dB per channel

## What You Modify
- `sdk/shaders/compress/bc5.hlsl` (orchestration)
- `sdk/shaders/compress/bc4.hlsl` (shared algorithm)

## Optimization Strategies

### Normal-Map Specific
- **Angular error optimization**: instead of minimizing per-channel MSE, minimize angular error of reconstructed normals
- **Correlated channel endpoints**: X and Y normals often correlate — joint optimization could help
- **Constrained range**: normal map values are typically in [−1, 1] → [0, 1] after bias, so use full 0-255 range

### Mostly, improve BC4 independently
BC5 quality = 2× BC4 quality. Focus BC4 research first, add normal-specific tricks later.

## Experiment Loop
Same as BC1: edit → commit → build → run → check → keep/discard
