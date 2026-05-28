@echo off
cd /d "g:\work\tech\infra\gpu_texture_compress"
setlocal enabledelayedexpansion

echo === Running All Format Baselines ===
echo.

for %%F in (quick_bc1.json quick_bc7.json quick_bc4.json quick_bc5.json quick_astc_4x4.json quick_astc_6x6.json) do (
    echo [TEST] %%F
    build\src\Release\gtc_runner.exe --config experiments/configs/%%F --shader-dir sdk/shaders --data-dir . 2>&1 | findstr "format: avg_psnr avg_ssim avg_time_ms status:"
    echo.
)

echo === Baseline Complete ===
