# GPU Texture Compression

GPU实时纹理压缩研究项目 — 基于 autoresearch 模式，使用 AI Agent 自主优化压缩算法。

## 项目目标

研发一套高性能 GPU 纹理压缩 Shader SDK，支持：
- **BCn 全量格式**: BC1, BC3, BC4, BC5, BC6H, BC7
- **ASTC 全14种 block size**: 4×4 到 12×12

最终交付物: `sdk/` 目录下的独立 shader 代码库。

## 项目结构

```
├── sdk/                        ★ 最终交付物 — Shader SDK
│   ├── README.md               SDK 文档
│   ├── include/                格式定义头文件
│   └── shaders/
│       ├── common/             共享工具 (interface, color_space, endpoint_fit)
│       ├── compress/           纯压缩函数 (可被fragment shader直接include)
│       └── dispatch/           Compute shader入口 (20个格式)
├── src/                        实验框架 (评估工具, 非交付物)
├── experiments/
│   ├── program.md              Autoresearch 主指令
│   ├── programs/               各格式独立研究计划
│   └── configs/                实验配置
├── external/                   Git submodules
│   └── SDL/                    SDL3 (GPU 抽象层)
├── data/src_texture/           测试数据集
└── deps/                       参考实现 (gitignored)
    ├── astc-encoder/           ARM ASTC 官方编码器
    ├── astc_encoder/           GPU ASTC 4x4/6x6 compute shader 参考
    └── DirectXTex/             Microsoft BCn 官方库
```

## 快速开始

### 环境要求
- Windows 10/11
- Visual Studio 2022 (或 Build Tools)
- CMake 3.24+
- Vulkan SDK (包含 dxc.exe with SPIRV codegen)
- Git with submodules

### 构建

```bash
git submodule update --init --recursive
cmake -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target gtc_runner
```

### 运行

```bash
# 查看 GPU 信息
build\src\Release\gtc_runner.exe --info

# 运行 BC1 基准测试
build\src\Release\gtc_runner.exe --config experiments/configs/quick_bc1.json \
    --shader-dir sdk/shaders --data-dir .

# 运行全格式测试 (20格式)
build\src\Release\gtc_runner.exe --config experiments/configs/full_sweep.json \
    --shader-dir sdk/shaders --data-dir .
```

## Autoresearch 模式

基于 [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) 模式，AI Agent 自主循环优化压缩 shader。

### 快速开始实验

**Step 1: 选择目标格式**

```bash
# 查看可用的研究计划
ls experiments/programs/
# → bc1.md  bc3.md  bc4.md  bc5.md  bc6h.md  bc7.md  astc.md
```

**Step 2: 读取研究计划**

研究计划包含：目标函数签名、当前baseline描述、优化策略路线图、官方源码参考路径。

```bash
# 以 BC7 为例
cat experiments/programs/bc7.md
```

**Step 3: 创建实验分支**

```bash
git checkout -b autoresearch/bc7
```

**Step 4: 运行实验循环**

```bash
# 修改 shader
code sdk/shaders/compress/bc7.hlsl

# 提交
git add sdk/shaders/compress/bc7.hlsl && git commit -m "BC7: add mode 5 support"

# 构建 (增量编译很快)
cmake --build build --config Release --target gtc_runner

# 运行评估
build\src\Release\gtc_runner.exe \
    --config experiments/configs/quick_bc7.json \
    --shader-dir sdk/shaders --data-dir .

# 查看结果
# → format: BC7  avg_psnr: 42.5  avg_ssim: 0.995  avg_time_ms: 1.2

# 如果 PSNR 提升 → 保留提交，继续下一个实验
# 如果 PSNR 下降 → git reset --hard HEAD~1，尝试其他方向
```

**Step 5: 查看实验历史**

```bash
cat experiments/results/quick_bc7.tsv
# commit  format  avg_psnr  avg_ssim  avg_flip  time_ms  status  description
# abc1234 BC7     39.96     0.992     0.012     0.35     keep    baseline mode 6
# def5678 BC7     42.50     0.995     0.008     1.20     keep    add mode 5
```

### Agent 自动化提示词 (Claude Code)

在项目根目录启动 Claude Code，输入：

```
读取 experiments/programs/bc7.md，开始 autoresearch 实验循环。
```

Agent 会自动：
1. 读取研究计划获取策略指导
2. 修改 `sdk/shaders/compress/bc7.hlsl`
3. 编译、运行、评估
4. 根据结果 keep/discard
5. 无限循环直到手动中断

### 可用实验配置

| 配置文件 | 用途 |
|----------|------|
| `configs/quick_bc1.json` | BC1 快速测试 (3张纹理) |
| `configs/quick_bc7.json` | BC7 快速测试 |
| `configs/quick_astc_4x4.json` | ASTC 4x4 快速测试 |
| `configs/quick_astc_6x6.json` | ASTC 6x6 快速测试 |
| `configs/bcn_test.json` | 全部BCn (1张纹理) |
| `configs/astc_sweep.json` | 全部ASTC (2张纹理) |
| `configs/full_sweep.json` | 全部20格式 (3张纹理) |

### SDK 文件结构 (Agent 可修改的范围)

```
sdk/shaders/compress/    ← Agent 优化这些文件
├── bc1.hlsl             纯函数: uint2 compress_bc1(float3 pixels[16])
├── bc3.hlsl             纯函数: uint4 compress_bc3(float4 pixels[16])
├── bc4.hlsl             纯函数: uint2 compress_bc4(float values[16])
├── bc5.hlsl             纯函数: uint4 compress_bc5(float2 pixels[16])
├── bc6h.hlsl            纯函数: uint4 compress_bc6h(float3 pixels[16])
├── bc7.hlsl             纯函数: uint4 compress_bc7(float4 pixels[16])
├── astc_4x4.hlsl        纯函数: uint4 compress_astc_4x4(float4 pixels[16])
├── astc_6x6.hlsl        纯函数: uint4 compress_astc_6x6(float4 pixels[36])
├── astc_8x8.hlsl        纯函数: uint4 compress_astc_8x8(float4 pixels[64])
├── ...                  (全14种ASTC block size)
├── astc_encode_core.hlsl  ASTC共享编码核心 (来自参考实现)
├── astc_tables.hlsl       ASTC量化/ISE表
├── astc_ise.hlsl          ASTC Integer Sequence Encoding
└── astc_common.hlsl       ASTC通用工具
```

## 评估指标

| 指标 | 方向 | 说明 |
|------|------|------|
| PSNR | 越高越好 | 峰值信噪比 (dB) |
| SSIM | 越高越好 | 结构相似度 |
| FLIP | 越低越好 | 感知差异 |
| Time | 越低越好 | GPU 压缩耗时 (ms) |

## Baseline 结果 (2026-05-28)

Initial baseline — PCA endpoints + simple quantization, no iterative refinement.

### BCn Formats

| 格式 | PSNR (dB) | SSIM | Time (ms) | 算法描述 |
|------|-----------|------|-----------|----------|
| BC1 | 33.20 | 0.973 | 4.15 | PCA axis + RGB565 endpoints + 4-color palette |
| BC3 | 33.20 | 0.973 | 1.58 | BC1 color + BC4 alpha |
| BC4 | 9.74 | 0.243 | 0.56 | Min/max + 8-level palette + 3-bit indices |
| BC5 | 13.32 | 0.993 | 0.28 | 2× BC4 (R+G channels) |
| BC6H | 4.46 | 0.048 | 0.35 | Stub (Mode 11 bounding box) |
| BC7 | **39.96** | **0.992** | 0.35 | Mode 6 only (7-bit RGBA endpoints + 4-bit indices) |

### ASTC Formats

| 格式 | PSNR (dB) | SSIM | Time (ms) | 算法描述 |
|------|-----------|------|-----------|----------|
| ASTC 4×4 | 7.56 | 0.001 | 0.85 | 4×4 weight grid, QUANT_4, CEM8 min/max |
| ASTC 5×4 | 7.56 | 0.001 | 0.81 | 同上 (proportional grid mapping) |
| ASTC 5×5 | 7.56 | 0.001 | 0.72 | 同上 |
| ASTC 6×5 | 7.56 | 0.001 | 0.43 | 同上 |
| ASTC 6×6 | 7.56 | 0.001 | 0.42 | 同上 |
| ASTC 8×5 | 7.56 | 0.001 | 0.34 | 同上 |
| ASTC 8×6 | 7.56 | 0.001 | 0.45 | 同上 |
| ASTC 8×8 | 7.56 | 0.001 | 0.42 | 同上 |
| ASTC 10×5 | 7.56 | 0.001 | 0.48 | 同上 |
| ASTC 10×6 | 7.56 | 0.001 | 0.63 | 同上 |
| ASTC 10×8 | 7.56 | 0.001 | 0.64 | 同上 |
| ASTC 10×10 | 7.56 | 0.001 | 0.81 | 同上 |
| ASTC 12×10 | 7.56 | 0.001 | 1.34 | 同上 |
| ASTC 12×12 | 7.56 | 0.001 | 0.71 | 同上 |

**测试条件**: 3张 PNG 纹理 (1×2048² + 2×256²), Vulkan backend, Windows, measurement_runs=1

### 已知问题
- BC4 PSNR 偏低: 单通道格式对 RGB 测试图评估不太合理
- ASTC PSNR 极低: baseline encoder 太简单（固定4×4 weight grid + QUANT_4），需要autoresearch优化
- BC6H: stub encoder 输出接近全零，待实现

## 许可证

MIT
