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

基于 [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) 模式:

1. AI Agent 读取 `experiments/programs/<format>.md`
2. 修改 `sdk/shaders/compress/<format>.hlsl`
3. 自动: 编译 → 运行压缩 → 评估质量 → 保留/丢弃
4. 循环迭代，持续优化

```bash
# 启动 autoresearch (示例)
# Agent 读取 experiments/programs/bc7.md 获取策略指导
# 修改 sdk/shaders/compress/bc7.hlsl
# 跑: gtc_runner.exe --config experiments/configs/quick_bc7.json ...
# 看: avg_psnr 是否提升 → keep/discard
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
