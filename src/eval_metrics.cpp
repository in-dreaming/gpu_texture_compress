#include "eval_metrics.h"
#include <cmath>
#include <algorithm>
#include <cstdio>
#include <vector>

namespace gtc {

MetricsResult EvalMetrics::evaluate(const TextureData& original, const TextureData& reconstructed) {
    MetricsResult result;

    if (original.width != reconstructed.width || original.height != reconstructed.height) {
        printf("[EvalMetrics] ERROR: Dimension mismatch (%ux%u vs %ux%u)\n",
               original.width, original.height, reconstructed.width, reconstructed.height);
        return result;
    }

    result.psnr_db = compute_psnr(original, reconstructed);
    result.ssim = compute_ssim(original, reconstructed);
    result.flip = compute_flip(original, reconstructed);
    result.lpips_approx = compute_lpips_approx(original, reconstructed);

    return result;
}

double EvalMetrics::compute_psnr(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 0.0;
    if (a.width != b.width || a.height != b.height) return 0.0;

    size_t num_pixels = (size_t)a.width * a.height;
    size_t num_channels = std::min(a.channels, b.channels);
    // Only compare RGB (first 3 channels)
    num_channels = std::min(num_channels, (size_t)3);

    double sum_sq_error = 0.0;
    size_t count = 0;

    for (size_t i = 0; i < num_pixels; i++) {
        for (size_t c = 0; c < num_channels; c++) {
            double va = (double)a.pixels[i * a.channels + c];
            double vb = (double)b.pixels[i * b.channels + c];
            double diff = va - vb;
            sum_sq_error += diff * diff;
            count++;
        }
    }

    if (count == 0) return 0.0;
    double mse = sum_sq_error / (double)count;
    if (mse < 1e-10) return 100.0; // Perfect match

    double psnr = 10.0 * log10(255.0 * 255.0 / mse);
    return psnr;
}

double EvalMetrics::compute_ssim(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 0.0;
    if (a.width != b.width || a.height != b.height) return 0.0;

    // SSIM computation with 8x8 window (simplified from 11x11 Gaussian for performance)
    // Constants for SSIM
    const double C1 = (0.01 * 255.0) * (0.01 * 255.0);  // (K1*L)^2
    const double C2 = (0.03 * 255.0) * (0.03 * 255.0);  // (K2*L)^2

    uint32_t w = a.width;
    uint32_t h = a.height;
    const int win_size = 8;

    double total_ssim = 0.0;
    int window_count = 0;

    // Convert to luminance for SSIM (or use per-channel and average)
    auto get_lum = [](const uint8_t* px, uint32_t channels) -> double {
        if (channels >= 3) {
            return 0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2];
        }
        return (double)px[0];
    };

    for (uint32_t y = 0; y + win_size <= h; y += win_size / 2) {
        for (uint32_t x = 0; x + win_size <= w; x += win_size / 2) {
            double sum_a = 0, sum_b = 0;
            double sum_a2 = 0, sum_b2 = 0, sum_ab = 0;
            int n = 0;

            for (int wy = 0; wy < win_size; wy++) {
                for (int wx = 0; wx < win_size; wx++) {
                    uint32_t px_idx = ((y + wy) * w + (x + wx));
                    double va = get_lum(&a.pixels[px_idx * a.channels], a.channels);
                    double vb = get_lum(&b.pixels[px_idx * b.channels], b.channels);

                    sum_a += va;
                    sum_b += vb;
                    sum_a2 += va * va;
                    sum_b2 += vb * vb;
                    sum_ab += va * vb;
                    n++;
                }
            }

            double mean_a = sum_a / n;
            double mean_b = sum_b / n;
            double var_a = sum_a2 / n - mean_a * mean_a;
            double var_b = sum_b2 / n - mean_b * mean_b;
            double cov_ab = sum_ab / n - mean_a * mean_b;

            double numerator = (2.0 * mean_a * mean_b + C1) * (2.0 * cov_ab + C2);
            double denominator = (mean_a * mean_a + mean_b * mean_b + C1) * (var_a + var_b + C2);

            double ssim_val = numerator / denominator;
            total_ssim += ssim_val;
            window_count++;
        }
    }

    if (window_count == 0) return 0.0;
    return total_ssim / window_count;
}

double EvalMetrics::compute_flip(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 1.0;
    if (a.width != b.width || a.height != b.height) return 1.0;

    // Simplified FLIP implementation
    // FLIP computes color difference in Hunt-adjusted CIELAB space
    // + edge/feature detection
    // Here we use a simplified version: weighted color difference in LAB space

    size_t num_pixels = (size_t)a.width * a.height;
    double total_diff = 0.0;

    auto srgb_to_linear = [](double v) -> double {
        v /= 255.0;
        return (v <= 0.04045) ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    };

    auto linear_to_lab_l = [](double r, double g, double b_val) -> double {
        // Approximate luminance -> L*
        double y = 0.2126 * r + 0.7152 * g + 0.0722 * b_val;
        double l = (y > 0.008856) ? 116.0 * pow(y, 1.0 / 3.0) - 16.0 : 903.3 * y;
        return l;
    };

    for (size_t i = 0; i < num_pixels; i++) {
        size_t offset_a = i * a.channels;
        size_t offset_b = i * b.channels;

        double ra = srgb_to_linear((double)a.pixels[offset_a + 0]);
        double ga = srgb_to_linear((double)a.pixels[offset_a + 1]);
        double ba = srgb_to_linear((double)a.pixels[offset_a + 2]);

        double rb = srgb_to_linear((double)b.pixels[offset_b + 0]);
        double gb = srgb_to_linear((double)b.pixels[offset_b + 1]);
        double bb = srgb_to_linear((double)b.pixels[offset_b + 2]);

        // Simple perceptual color difference (deltaE-like)
        double la = linear_to_lab_l(ra, ga, ba);
        double lb = linear_to_lab_l(rb, gb, bb);

        double dl = (la - lb) / 100.0;  // Normalize to [0,1]
        double dr = ra - rb;
        double dg = ga - gb;
        double db = ba - bb;

        // Weighted: luminance difference + chrominance difference
        double diff = sqrt(dl * dl * 0.5 + (dr * dr + dg * dg + db * db) * 0.5);
        total_diff += std::min(diff, 1.0);
    }

    return total_diff / (double)num_pixels;
}

double EvalMetrics::compute_lpips_approx(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 1.0;
    if (a.width != b.width || a.height != b.height) return 1.0;

    // Approximate LPIPS using multi-scale gradient differences
    // This correlates reasonably well with true LPIPS without neural network

    size_t num_pixels = (size_t)a.width * a.height;
    uint32_t w = a.width;
    uint32_t h = a.height;

    auto get_gray = [](const uint8_t* px, uint32_t ch) -> double {
        if (ch >= 3) return (0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2]) / 255.0;
        return px[0] / 255.0;
    };

    // Compute gradient magnitude difference at multiple scales
    double total_diff = 0.0;
    int count = 0;

    // Scale 1: 1x1 pixel gradient
    for (uint32_t y = 1; y < h - 1; y++) {
        for (uint32_t x = 1; x < w - 1; x++) {
            size_t idx = (y * w + x);
            size_t idx_l = (y * w + x - 1);
            size_t idx_r = (y * w + x + 1);
            size_t idx_u = ((y - 1) * w + x);
            size_t idx_d = ((y + 1) * w + x);

            double ga_x = get_gray(&a.pixels[idx_r * a.channels], a.channels) -
                          get_gray(&a.pixels[idx_l * a.channels], a.channels);
            double ga_y = get_gray(&a.pixels[idx_d * a.channels], a.channels) -
                          get_gray(&a.pixels[idx_u * a.channels], a.channels);

            double gb_x = get_gray(&b.pixels[idx_r * b.channels], b.channels) -
                          get_gray(&b.pixels[idx_l * b.channels], b.channels);
            double gb_y = get_gray(&b.pixels[idx_d * b.channels], b.channels) -
                          get_gray(&b.pixels[idx_u * b.channels], b.channels);

            double grad_diff_x = ga_x - gb_x;
            double grad_diff_y = ga_y - gb_y;
            total_diff += sqrt(grad_diff_x * grad_diff_x + grad_diff_y * grad_diff_y);
            count++;
        }
    }

    if (count == 0) return 1.0;

    // Normalize to approximately [0, 1] range
    double avg_diff = total_diff / count;
    return std::min(avg_diff * 2.0, 1.0); // Scale factor for typical range
}

} // namespace gtc
