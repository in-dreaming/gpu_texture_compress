#pragma once

#include "texture_loader.h"
#include <cstdint>

namespace gtc {

struct MetricsResult {
    double psnr_db = 0.0;          // Peak Signal-to-Noise Ratio (higher = better)
    double ssim = 0.0;             // Structural Similarity [0,1] (higher = better)
    double flip = 0.0;             // FLIP perceptual difference [0,1] (lower = better)
    double lpips_approx = 0.0;     // Approximated LPIPS [0,1] (lower = better)
    double mse = 0.0;              // Mean Squared Error (raw)
};

class EvalMetrics {
public:
    // Compare original vs decompressed (reconstructed) image
    // Both must be RGBA8 format with same dimensions
    MetricsResult evaluate(const TextureData& original, const TextureData& reconstructed);

    // Individual metrics
    double compute_psnr(const TextureData& a, const TextureData& b);
    double compute_ssim(const TextureData& a, const TextureData& b);
    double compute_flip(const TextureData& a, const TextureData& b);
    double compute_lpips_approx(const TextureData& a, const TextureData& b);
};

} // namespace gtc
