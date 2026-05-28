# BC6H Compression — Autoresearch Program

## Target
`sdk/shaders/compress/bc6h.hlsl` → `uint4 compress_bc6h(float3 pixels[16])`

BC6H: HDR RGB, 8bpp, 4x4 block → 128-bit output. 14 encoding modes with varying partition/endpoint precision.

## Current Baseline
**STUB** — outputs a simple Mode 11 block (bounding box endpoints). Barely functional.

## Metrics Goal
- **avg_psnr**: maximize (HDR PSNR computed in log space)
- Typical target: 35-45 dB for HDR content
- **avg_time_ms**: < 10ms per 1K texture

## What You Modify
Only: `sdk/shaders/compress/bc6h.hlsl`

## BC6H Format Overview
- 14 modes (numbered 0-13), selected by first 2-5 bits
- Each mode specifies: partition count (1 or 2), endpoint precision, delta encoding
- Endpoints are half-float or shared-exponent format
- 16× 3-bit or 4-bit indices (depending on partition count)

## Optimization Strategies (Roadmap)

### Phase 1: Single-Mode Baseline
- Implement Mode 11 properly (1 partition, 16-bit endpoints per channel, 4-bit indices)
- This is the simplest mode with highest endpoint precision
- Result: ~30 dB for most HDR content

### Phase 2: Multi-Mode Selection
- Implement 2-3 best modes (Mode 11, Mode 3, Mode 7)
- Try each mode, pick lowest error
- Significant quality jump

### Phase 3: Partition Search
- Modes with 2 partitions (32 partition patterns) 
- For each candidate partition, compute separate endpoints per subset
- Major quality improvement for complex blocks

### Phase 4: Delta Endpoint Optimization
- Most modes use delta encoding (base + offset endpoints)
- Optimize base and delta to minimize quantization error
- Precision: shared vs per-channel optimization

## Reference Source Code (官方库)

### DirectXTex (BCn 官方库)
- `deps/DirectXTex/DirectXTex/BC6HBC7.cpp` — BC6H 完整编码实现 (CPU)
- `deps/DirectXTex/DirectXTex/Shaders/BC6HEncode.hlsl` — **GPU compute shader实现!**
- `deps/DirectXTex/DirectXTex/BCDirectCompute.cpp` — GPU dispatch逻辑

### DirectXTex BC6HEncode.hlsl 关键知识
- Microsoft官方实现了BC6H的GPU compute shader压缩
- 半浮点端点编码 (half-float shared exponent)
- Mode搜索 + partition搜索
- Delta endpoint 编码

### 关键算法知识
- BC6H有14种mode(编号1-14, 用前2-5 bits标识)
- Mode 11: 1 partition, 全精度(16-bit per channel), 最适合做baseline
- Mode 3: 2 partitions, 10-bit endpoints, 适合复杂HDR block
- 端点是half-float或shared-exponent格式, 不是简单的integer
- signed和unsigned两种变体(BC6H_SF16 vs BC6H_UF16)

## Experiment Loop
Same as BC1: edit → commit → build → run → check → keep/discard
