# ASTC Compression — Autoresearch Program

## Architecture

每个 block size 独立一个压缩函数文件，共享公共工具代码：
```
sdk/shaders/compress/
├── astc_common.hlsl         # 公共: void-extent, ISE编码, block组装, reverse_byte
├── astc_4x4.hlsl            # uint4 compress_astc_4x4(float4 pixels[16])
├── astc_5x4.hlsl            # uint4 compress_astc_5x4(float4 pixels[20])
├── ...
└── astc_12x12.hlsl          # uint4 compress_astc_12x12(float4 pixels[144])
```

## 核心知识（摘自参考实现）

### 参考源码位置
- `deps/astc_encoder/ASTC_Encode.hlsl` — GPU compute shader实现(4x4, 6x6)，最直接的参考
- `deps/astc_encoder/ASTC_Table.hlsl` — 量化表、ISE编码表
- `deps/astc_encoder/ASTC_IntegerSequenceEncoding.hlsl` — ISE trit/quint编码
- `deps/astc-encoder/Source/astcenc_compress_symbolic.cpp` — ARM官方CPU参考

### ASTC Block 结构 (128 bits)
```
Bits [10:0]    = Block Mode (weight grid尺寸 + 量化级别 + plane数)
Bits [12:11]   = Partition Count - 1 (0=单partition)
Bits [16:13]   = CEM (Color Endpoint Mode)
Bits [17..N]   = Endpoint Data (ISE编码)
Bits [127..M]  = Weight Data (从MSB端存储, byte-reversed)
```

### Weight Grid 到 Pixel 的映射
- **4x4 block, 4x4 grid**: 1:1映射，grid[i] = pixel[i]
- **6x6 block, 4x4 grid**: 需要双线性插值
  ```
  参考实现中的映射表(deps/astc_encoder/ASTC_Encode.hlsl:335):
  idx_grids[16] = {0,1,4,5, 6,7,10,11, 24,25,28,29, 30,31,34,35}
  wt_grids[16]  = 对应的插值权重
  float4 sum = sample_texel(texels, idx_grids[i], wt_grids[i])
  ```
- **大尺寸block**: grid position → pixel coordinate 按比例映射:
  `px = gx * (block_w - 1) / (grid_w - 1)`

### ISE (Integer Sequence Encoding)
ASTC 的量化不是简单的n-bit，而是用 trit(3值)/quint(5值) 编码：
- QUANT_6 (range 0-5): trit编码, 每3个值用8.67 bits
- QUANT_12 (range 0-11): quint编码, 每5个值用16.67 bits  
- QUANT_20 (range 0-19): trit+quint混合

参考 `deps/astc_encoder/ASTC_IntegerSequenceEncoding.hlsl` 中的编码表。

### Block Mode 编码规则 (bits [10:0])
参考实现中选择的 mode:
- 4x4, QUANT_12: block_mode = 某个特定值 (见ASTC_Table.hlsl)
- 6x6用4x4 grid, QUANT_12: 另一个值

具体编码规则较复杂，参见 ASTC spec Table C.2.8。baseline可以hard-code一个已知好的mode值。

## Reference Source Code (官方库)

### deps/astc_encoder/ — GPU Compute Shader实现 (最直接参考)
- `ASTC_Encode.hlsl` — 核心压缩逻辑(4x4, 6x6), D3D11 compute shader
- `ASTC_Table.hlsl` — 量化表、block mode表、ISE编码查找表
- `ASTC_IntegerSequenceEncoding.hlsl` — ISE trit/quint编码实现
- `astc_encode.h` — C++ host端接口

**关键实现细节(摘自ASTC_Encode.hlsl):**
- 4x4: weight grid 1:1映射pixel, 用QUANT_12
- 6x6: 用 `idx_grids[16]` 和 `wt_grids[16]` 表做双线性插值到4x4 grid
- 端点: PCA主轴 → 投影 → min/max → CEM 8/12
- Weight: 投影到端点轴 → quantize → ISE编码
- Block组装: `assemble_block()` 函数处理bit packing + byte reverse

### deps/astc-encoder/ — ARM官方库 (CPU, 全功能参考)
- `Source/astcenc_compress_symbolic.cpp` — 主压缩流程
- `Source/astcenc_find_best_partitioning.cpp` — partition搜索
- `Source/astcenc_ideal_endpoints_and_weights.cpp` — 最优端点/权重计算
- `Source/astcenc_integer_sequence.cpp` — ISE编解码
- `Source/astcenc_color_quantize.cpp` — 颜色量化
- `Source/astcenc_weight_align.cpp` — 权重对齐优化
- `Source/astcenc_block_sizes.cpp` — 各block size的参数表
- `Source/astcenc_symbolic_physical.cpp` — symbolic→physical block转换
- `Source/astcenc_partition_tables.cpp` — partition pattern表

## 各尺寸优化策略

### 4x4 (16 pixels, 8.00 bpp) — 最高质量目标
- Grid = 4x4 (1:1映射)，可用 QUANT_12 甚至 QUANT_20
- 有最多bits用于weight，应追求最高精度
- 策略：PCA端点 + 高精度weight量化 + 迭代优化
- **目标 PSNR**: 38-45 dB

### 5x4, 5x5 (20-25 pixels, 5.12-6.40 bpp)
- Grid可用 5x4 或 4x4，取决于bit budget
- 5x4有20个pixel但grid最多4x4=16 weight → 少量插值
- 策略：4x4 grid + 简单nearest采样 或 bilinear

### 6x5, 6x6 (30-36 pixels, 3.56-4.27 bpp)
- Grid = 4x4 (16 weights)，需要双线性插值
- **参考实现有完整的6x6方案** — 直接参考 `deps/astc_encoder/ASTC_Encode.hlsl`
- 策略：参考实现的 idx_grids/wt_grids 表 + PCA端点
- **目标 PSNR**: 32-38 dB

### 8x5, 8x6, 8x8 (40-64 pixels, 2.00-3.20 bpp)
- Grid = 4x4 或 3x3，从大量pixel采样到少量grid点
- bit budget紧张：weight用低precision (QUANT_4 或 QUANT_6)
- 策略：平均采样(每个grid点覆盖多个pixel) + min/max端点
- **目标 PSNR**: 28-35 dB

### 10x5-12x12 (50-144 pixels, 0.89-2.56 bpp)
- Grid = 3x3 或 4x4，极大的pixel-to-grid比
- 最低bit budget，质量损失最大
- 策略：区域平均采样 + 低精度weight + 可能需要2-partition
- **目标 PSNR**: 24-32 dB

## Run
```bash
# 测试单个尺寸
build\Release\gtc_runner.exe --config experiments/configs/quick_astc_4x4.json --shader-dir sdk/shaders --data-dir .
# 测试全部ASTC
build\Release\gtc_runner.exe --config experiments/configs/full_sweep.json --shader-dir sdk/shaders --data-dir .
```

## What You Modify
- `sdk/shaders/compress/astc_WxH.hlsl` — 对应尺寸的压缩函数
- `sdk/shaders/compress/astc_common.hlsl` — 共享工具（影响所有尺寸）

## Experiment Loop
```
LOOP:
1. 选择一个目标尺寸 (如 astc_4x4)
2. Edit sdk/shaders/compress/astc_4x4.hlsl
3. git commit -m "ASTC 4x4: description"
4. cmake --build build --config Release
5. gtc_runner.exe --config experiments/configs/quick_astc_4x4.json ... > run.log 2>&1
6. findstr "avg_psnr" run.log
7. If improved → keep, else → git reset --hard HEAD~1
```
