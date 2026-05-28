# BC7 Compression — Autoresearch Program

## Target
`sdk/shaders/compress/bc7.hlsl` → `uint4 compress_bc7(float4 pixels[16])`

BC7: RGBA 8bpp, 4x4 block → 128-bit output. 8 encoding modes with varying partition/precision tradeoffs.

## Current Baseline
**Mode 6 only** — 1 partition, 7-bit RGBA endpoints + P-bit, 4-bit indices.
Simple PCA on RGBA → project → quantize → indices.

## Metrics Goal
- **avg_psnr**: maximize (typical target: 40-50 dB)
- **avg_time_ms**: < 10ms per 1K texture

## What You Modify
Only: `sdk/shaders/compress/bc7.hlsl`

## BC7 Mode Summary
| Mode | Partitions | Subsets | Color Bits | Alpha Bits | Index Bits | P-bits |
|------|-----------|---------|------------|------------|------------|--------|
| 0 | 16 | 3 | 4 | 0 | 3 | 1 each |
| 1 | 64 | 2 | 6 | 0 | 3 | 1 shared |
| 2 | 64 | 3 | 5 | 0 | 2 | 0 |
| 3 | 64 | 2 | 7 | 0 | 2 | 1 each |
| 4 | 1 | 1 | 5 | 6 | 2+3 | 0 |
| 5 | 1 | 1 | 7 | 8 | 2+2 | 0 |
| 6 | 1 | 1 | 7 | 7 | 4 | 1 each |
| 7 | 64 | 2 | 5 | 5 | 2 | 1 each |

## Optimization Strategies (Roadmap)

### Phase 1: Improve Mode 6 (current)
- Better PCA initialization for 4D RGBA
- Iterative endpoint refinement (quantize → indices → least-squares → repeat)
- P-bit search (try both P-bit values, pick lower error)
- **Expected gain**: +3-5 dB

### Phase 2: Add Mode 5 (second mode)
- Mode 5: 7-bit color + 8-bit alpha, separate 2-bit color/alpha indices
- Great for opaque blocks (alpha = 255) and blocks with smooth alpha
- Selection heuristic: if alpha variance low → Mode 5, else → Mode 6

### Phase 3: Add Mode 1 (two-subset)
- Mode 1: 2 subsets with 6-bit color, 64 partition patterns
- For high-variance blocks, splitting into 2 subsets helps significantly
- Partition search: try top-K partitions by color variance split

### Phase 4: Multi-Mode Decision
- Block classification: compute variance, alpha range, spatial gradient
- Fast heuristic to select 2-3 candidate modes
- Try each candidate, pick lowest error
- **Expected gain**: +5-8 dB over Mode 6 alone

### Phase 5: Advanced Techniques
- Anchor index fixup (bit saving trick for 2+ subset modes)
- Rotation mode optimization (Mode 4/5 can rotate channels)
- Endpoint quantization search (try nearby quantized values)

## Performance Considerations
- Mode 6 only = fastest (single code path, no divergence)
- Multi-mode = slower but much higher quality
- Can use QualityLevel to control: 0=Mode6 only, 1=Mode5+6, 2=full search

## Reference
- `deps/DirectXTex/BC7Encode.cpp` — Microsoft's CPU reference
- BC7 spec: https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc7-format

## Reference Source Code (官方库)

### DirectXTex (BCn 官方库)
- `deps/DirectXTex/DirectXTex/BC6HBC7.cpp` — BC7 完整编码实现 (CPU)
- `deps/DirectXTex/DirectXTex/Shaders/BC7Encode.hlsl` — **GPU compute shader实现!**
- `deps/DirectXTex/DirectXTex/BCDirectCompute.cpp` — GPU dispatch逻辑

### DirectXTex BC7Encode.hlsl 关键知识
- Microsoft官方实现了BC7的GPU compute shader压缩
- 支持多mode搜索 + partition搜索
- 使用 shared memory 缓存block像素
- Endpoint量化用查表法
- 可直接参考其mode选择逻辑和bit packing

### 关键算法知识
- Mode 6: 最简单也最常用(无partition, 4-bit index, 高精度endpoint)
- Mode 1: 2 subsets, 3-bit index, 适合有两种主色调的block
- Mode 4/5: 分离的color/alpha index, 适合alpha变化独立于color的情况
- Anchor index fixup: 每个subset的第一个index最高位被迫为0(节省1bit)

## Experiment Loop
Same as BC1: edit → commit → build → run → check → keep/discard
