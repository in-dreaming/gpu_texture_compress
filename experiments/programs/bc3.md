# BC3 Compression — Autoresearch Program

## Target
`sdk/shaders/compress/bc3.hlsl` → `uint4 compress_bc3(float4 pixels[16])`

BC3: RGBA 8bpp, 4x4 block → 128-bit output (BC4 alpha block + BC1 color block)

## Current Baseline
Split RGBA → BC4 on alpha, BC1 on RGB → concatenate.

## Dependencies
- `compress/bc1.hlsl` — color portion
- `compress/bc4.hlsl` — alpha portion

## Metrics Goal
- **avg_psnr**: maximize (combination of color + alpha quality)
- Typical target: color 33-38 dB, alpha 42-48 dB

## What You Modify
- `sdk/shaders/compress/bc3.hlsl` (orchestration)
- Can also improve `compress/bc1.hlsl` and `compress/bc4.hlsl` (shared)

## Optimization Strategies

### Beyond Simple Split
- **Correlated alpha-color optimization**: if alpha varies with luminance, consider weighting
- **Pre-multiply awareness**: if textures are pre-multiplied alpha, optimize differently

### Mostly, improve BC1 + BC4 independently
BC3 quality is directly the sum of its parts. Focus BC1 and BC4 research first.

## Experiment Loop
Same as BC1: edit → commit → build → run → check → keep/discard
