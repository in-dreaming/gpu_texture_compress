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

## Baseline 结果

| 格式 | PSNR | SSIM | Time(ms) |
|------|------|------|----------|
| BC1 | 33.1 dB | 0.973 | ~5ms |
| BC7 | (pending decompressor) | — | ~3ms |
| ASTC 4×4 | (pending decompressor) | — | ~3ms |

## 许可证

MIT
