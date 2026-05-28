# BC1 Compression — Autoresearch Program

## Target
`sdk/shaders/compress/bc1.hlsl` → `uint2 compress_bc1(float3 pixels[16])`

BC1: RGB 4bpp, 4x4 block → 64-bit output (2× RGB565 endpoints + 16× 2-bit indices)

## Current Baseline
PCA axis → project to get endpoints → quantize RGB565 → 4-color palette → nearest-index.

## Metrics Goal
- **avg_psnr**: maximize (typical target: 33-38 dB)
- **avg_time_ms**: < 5ms per 1K texture

## Run
```bash
build\Release\gtc_runner.exe --config experiments/configs/quick_bc1.json --shader-dir sdk/shaders --data-dir .
```

## What You Modify
Only: `sdk/shaders/compress/bc1.hlsl`
- Function signature `uint2 compress_bc1(float3 pixels[16])` must not change
- Can also modify `sdk/shaders/common/endpoint_fit.hlsl` (shared utility)

## Optimization Strategies

### Endpoint Selection
- **Iterative refinement**: after index assignment, recompute optimal endpoints via least-squares, repeat 2-3 iterations
- **Min/max bounding box diagonal** as initial guess (faster than PCA, sometimes better)
- **Inset endpoints**: shrink endpoints inward by 1/16 to reduce error at palette boundaries

### Index Assignment
- **Weighted error**: weight green channel 2× (human vision sensitivity)
- **Perceptual weighting**: use `(2*R + 4*G + B)/7` distance instead of Euclidean RGB

### Palette Tricks
- After quantizing to RGB565, decode back and rebuild palette for exact matching
- Try both 4-color mode (ep0 > ep1) and 3-color+transparent mode — pick lower error

### Performance
- Avoid divergent branches — prefer arithmetic solutions
- Use `[unroll]` for fixed-iteration loops
- Single-pass refinement (encode → evaluate → refine → re-encode) within 2 iterations

## Reference Source Code (官方库)

### DirectXTex (BCn 官方库)
- `deps/DirectXTex/DirectXTex/BC.h` — BC1-BC5 数据结构定义
- `deps/DirectXTex/DirectXTex/BC.cpp` — BC1/BC2/BC3 编码/解码实现
- `deps/DirectXTex/DirectXTex/BC4BC5.cpp` — BC4/BC5 编码/解码
- 关键函数: `D3DXEncodeBC1()`, 端点选取逻辑, index assignment

### 关键算法知识 (从官方库提取)
- BC1 4-color mode: ep0_565 > ep1_565 表示4色模式, 否则3色+透明
- RGB565 量化: R=5bit, G=6bit, B=5bit
- 索引顺序: pixel[0]在bits[0:1], pixel[15]在bits[30:31]
- 端点优化: Microsoft实现用了 bounding box + PCA + iterative refinement

## Impact
BC1 is also used inside BC3 (color portion). Improvements here benefit BC3 too.

## Experiment Loop
```
LOOP:
1. Edit sdk/shaders/compress/bc1.hlsl
2. git commit -m "BC1: description"
3. cmake --build build --config Release
4. gtc_runner.exe --config experiments/configs/quick_bc1.json --shader-dir sdk/shaders --data-dir . > run.log 2>&1
5. findstr "avg_psnr avg_time_ms" run.log
6. If improved → keep, else → git reset --hard HEAD~1
```
