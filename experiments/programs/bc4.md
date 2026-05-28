# BC4 Compression — Autoresearch Program

## Target
`sdk/shaders/compress/bc4.hlsl` → `uint2 compress_bc4(float values[16])`

BC4: Single channel (Red), 4bpp, 4x4 block → 64-bit output (2× 8-bit endpoints + 16× 3-bit indices)

## Current Baseline
Min/max endpoints → 8-level palette (6 interpolated + 2 endpoint) → nearest 3-bit index.

## Metrics Goal
- **avg_psnr**: maximize (typical target: 42-48 dB for single channel)
- **avg_time_ms**: < 2ms per 1K texture

## Run
```bash
build\Release\gtc_runner.exe --config experiments/configs/quick_bc4.json --shader-dir sdk/shaders --data-dir .
```

## What You Modify
Only: `sdk/shaders/compress/bc4.hlsl`
- Function signature `uint2 compress_bc4(float values[16])` must not change

## Optimization Strategies

### Endpoint Optimization
- **Optimal endpoints search**: don't use raw min/max — try inset by 1/32 or brute-force nearby values
- **Iterative refinement**: assign indices → compute optimal endpoints via least-squares → repeat
- **Mode selection**: BC4 has two modes:
  - Mode 1 (ep0 > ep1): 8 interpolated values (for smooth gradients)
  - Mode 2 (ep0 <= ep1): 6 interpolated + 0 + 255 (for data with 0/255 extremes)
  - Pick mode based on block content

### Index Assignment
- After endpoint quantization, always reassign indices using the actual decoded palette
- For borderline cases, try both neighbors and pick lower error

### Performance
- Very simple algorithm — mostly arithmetic, almost no divergence
- Profile: is 16-pixel loop the bottleneck, or is it the palette interpolation?

## Reference Source Code (官方库)

### DirectXTex (BCn 官方库)
- `deps/DirectXTex/DirectXTex/BC4BC5.cpp` — BC4/BC5 编码/解码实现
- 关键函数: `OptimizeAlpha()` — 最优端点搜索算法
- 实现了: iterative refinement + exhaustive endpoint search

### 关键算法知识 (从官方库提取)
- 8-value mode (ep0 > ep1): values = {ep0, ep1, 6/7*ep0+1/7*ep1, ..., 1/7*ep0+6/7*ep1}
- 6-value mode (ep0 <= ep1): values = {ep0, ep1, 4/5*ep0+1/5*ep1, ..., 1/5*ep0+4/5*ep1, 0, 255}
- 3-bit indices packed in 48 bits (6 bytes), pixel[0]在bits[16:18]
- OptimizeAlpha: Microsoft用最小二乘法迭代搜索最优的8-bit endpoints

## Impact
BC4 is used inside BC3 (alpha channel) and BC5 (both channels). Improvements here benefit BC3 and BC5.

## Experiment Loop
Same as BC1: edit → commit → build → run → check → keep/discard
