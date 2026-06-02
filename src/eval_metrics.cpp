#include "eval_metrics.h"
#include <cmath>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <vector>

namespace gtc {

// ============================================================================
// HDR helpers (when both inputs are float HDR)
// ============================================================================

namespace {

// HDR PSNR using image-specific peak value:
//   peak = max(reference) (clamped to >= 1.0 to avoid log of tiny values)
//   PSNR = 10 * log10(peak^2 / MSE)
// This matches the standard formulation when normalized to [0, peak].
// For very low-luminance HDR content where peak < 1.0 would inflate PSNR,
// we floor at 1.0 for stability and comparability across images.
double compute_psnr_hdr_internal(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 0.0;
    if (a.width != b.width || a.height != b.height) return 0.0;

    const float* af = reinterpret_cast<const float*>(a.pixels.data());
    const float* bf = reinterpret_cast<const float*>(b.pixels.data());

    size_t num_pixels = (size_t)a.width * a.height;
    size_t num_channels = std::min(a.channels, b.channels);
    num_channels = std::min(num_channels, (size_t)3);

    // Peak from reference image (RGB only)
    double peak = 0.0;
    for (size_t i = 0; i < num_pixels; i++) {
        for (size_t c = 0; c < num_channels; c++) {
            double v = (double)af[i * a.channels + c];
            if (std::isfinite(v) && v > peak) peak = v;
        }
    }
    if (peak < 1.0) peak = 1.0;  // floor at 1.0 for stable metric across exposures

    double sum_sq = 0.0;
    size_t count = 0;
    for (size_t i = 0; i < num_pixels; i++) {
        for (size_t c = 0; c < num_channels; c++) {
            double va = (double)af[i * a.channels + c];
            double vb = (double)bf[i * b.channels + c];
            // Guard against NaN/Inf
            if (!std::isfinite(va) || !std::isfinite(vb)) continue;
            double d = va - vb;
            sum_sq += d * d;
            count++;
        }
    }

    if (count == 0) return 0.0;
    double mse = sum_sq / (double)count;
    if (mse < 1e-12) return 100.0;
    return 10.0 * std::log10(peak * peak / mse);
}

// HDR SSIM: window-based, with luminance scaled by per-image peak.
double compute_ssim_hdr_internal(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 0.0;
    if (a.width != b.width || a.height != b.height) return 0.0;

    const float* af = reinterpret_cast<const float*>(a.pixels.data());
    const float* bf = reinterpret_cast<const float*>(b.pixels.data());

    uint32_t w = a.width;
    uint32_t h = a.height;
    const int win_size = 8;

    // Determine peak (use Rec.709 luminance for SSIM; cap at 1.0 floor)
    double peak_lum = 0.0;
    size_t num_pixels = (size_t)w * h;
    for (size_t i = 0; i < num_pixels; i++) {
        double r = af[i * a.channels + 0];
        double g = (a.channels > 1) ? af[i * a.channels + 1] : r;
        double bl = (a.channels > 2) ? af[i * a.channels + 2] : r;
        if (!std::isfinite(r) || !std::isfinite(g) || !std::isfinite(bl)) continue;
        double lum = 0.2126 * r + 0.7152 * g + 0.0722 * bl;
        if (lum > peak_lum) peak_lum = lum;
    }
    if (peak_lum < 1.0) peak_lum = 1.0;

    const double C1 = (0.01 * peak_lum) * (0.01 * peak_lum);
    const double C2 = (0.03 * peak_lum) * (0.03 * peak_lum);

    auto get_lum = [](const float* px, uint32_t channels) -> double {
        if (channels >= 3) {
            double r = px[0], g = px[1], b = px[2];
            if (!std::isfinite(r) || !std::isfinite(g) || !std::isfinite(b)) return 0.0;
            return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }
        double r = px[0];
        return std::isfinite(r) ? r : 0.0;
    };

    double total_ssim = 0.0;
    int window_count = 0;

    for (uint32_t y = 0; y + win_size <= h; y += win_size / 2) {
        for (uint32_t x = 0; x + win_size <= w; x += win_size / 2) {
            double sum_a = 0, sum_b = 0;
            double sum_a2 = 0, sum_b2 = 0, sum_ab = 0;
            int n = 0;
            for (int wy = 0; wy < win_size; wy++) {
                for (int wx = 0; wx < win_size; wx++) {
                    uint32_t px_idx = ((y + wy) * w + (x + wx));
                    double va = get_lum(&af[px_idx * a.channels], a.channels);
                    double vb = get_lum(&bf[px_idx * b.channels], b.channels);
                    sum_a += va; sum_b += vb;
                    sum_a2 += va * va; sum_b2 += vb * vb;
                    sum_ab += va * vb;
                    n++;
                }
            }
            double mean_a = sum_a / n, mean_b = sum_b / n;
            double var_a = sum_a2 / n - mean_a * mean_a;
            double var_b = sum_b2 / n - mean_b * mean_b;
            double cov_ab = sum_ab / n - mean_a * mean_b;
            double num = (2.0 * mean_a * mean_b + C1) * (2.0 * cov_ab + C2);
            double den = (mean_a * mean_a + mean_b * mean_b + C1) * (var_a + var_b + C2);
            double ssim_val = (den > 1e-30) ? num / den : 0.0;
            // Clamp to handle numerical edge cases
            if (ssim_val < -1.0) ssim_val = -1.0;
            if (ssim_val > 1.0) ssim_val = 1.0;
            total_ssim += ssim_val;
            window_count++;
        }
    }

    if (window_count == 0) return 0.0;
    return total_ssim / window_count;
}

// HDR FLIP/LPIPS: simplified — apply Reinhard tone mapping then use LDR formulas
// to give a comparable perceptual value. This is approximate; production code
// would use HDR-VDP-2 or similar.
double compute_flip_hdr_internal(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 1.0;
    if (a.width != b.width || a.height != b.height) return 1.0;

    const float* af = reinterpret_cast<const float*>(a.pixels.data());
    const float* bf = reinterpret_cast<const float*>(b.pixels.data());

    size_t num_pixels = (size_t)a.width * a.height;
    double total_diff = 0.0;
    size_t count = 0;

    auto reinhard = [](double v) {
        if (!std::isfinite(v) || v < 0.0) return 0.0;
        return v / (1.0 + v);
    };

    for (size_t i = 0; i < num_pixels; i++) {
        double ra = reinhard(af[i * a.channels + 0]);
        double ga = (a.channels > 1) ? reinhard(af[i * a.channels + 1]) : ra;
        double ba = (a.channels > 2) ? reinhard(af[i * a.channels + 2]) : ra;
        double rb = reinhard(bf[i * b.channels + 0]);
        double gb = (b.channels > 1) ? reinhard(bf[i * b.channels + 1]) : rb;
        double bb = (b.channels > 2) ? reinhard(bf[i * b.channels + 2]) : rb;
        double dr = ra - rb;
        double dg = ga - gb;
        double db = ba - bb;
        // Simple tone-mapped Euclidean diff
        double d = std::sqrt(dr * dr + dg * dg + db * db) / std::sqrt(3.0);
        total_diff += std::min(d, 1.0);
        count++;
    }
    if (count == 0) return 1.0;
    return total_diff / (double)count;
}

double compute_lpips_hdr_internal(const TextureData& a, const TextureData& b) {
    if (a.pixels.empty() || b.pixels.empty()) return 1.0;
    if (a.width != b.width || a.height != b.height) return 1.0;

    const float* af = reinterpret_cast<const float*>(a.pixels.data());
    const float* bf = reinterpret_cast<const float*>(b.pixels.data());

    uint32_t w = a.width, h = a.height;

    auto reinhard_gray = [](const float* px, uint32_t ch) {
        double r = px[0];
        double g = (ch > 1) ? px[1] : r;
        double b = (ch > 2) ? px[2] : r;
        if (!std::isfinite(r)) r = 0.0;
        if (!std::isfinite(g)) g = 0.0;
        if (!std::isfinite(b)) b = 0.0;
        double lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        return lum / (1.0 + lum);
    };

    double total = 0.0;
    int count = 0;
    for (uint32_t y = 1; y + 1 < h; y++) {
        for (uint32_t x = 1; x + 1 < w; x++) {
            size_t idx_l = (y * w + x - 1);
            size_t idx_r = (y * w + x + 1);
            size_t idx_u = ((y - 1) * w + x);
            size_t idx_d = ((y + 1) * w + x);
            double ga_x = reinhard_gray(&af[idx_r * a.channels], a.channels)
                        - reinhard_gray(&af[idx_l * a.channels], a.channels);
            double ga_y = reinhard_gray(&af[idx_d * a.channels], a.channels)
                        - reinhard_gray(&af[idx_u * a.channels], a.channels);
            double gb_x = reinhard_gray(&bf[idx_r * b.channels], b.channels)
                        - reinhard_gray(&bf[idx_l * b.channels], b.channels);
            double gb_y = reinhard_gray(&bf[idx_d * b.channels], b.channels)
                        - reinhard_gray(&bf[idx_u * b.channels], b.channels);
            double dx = ga_x - gb_x;
            double dy = ga_y - gb_y;
            total += std::sqrt(dx * dx + dy * dy);
            count++;
        }
    }
    if (count == 0) return 1.0;
    return std::min(total / count * 2.0, 1.0);
}

} // anonymous namespace

MetricsResult EvalMetrics::evaluate(const TextureData& original, const TextureData& reconstructed) {
    MetricsResult result;

    if (original.width != reconstructed.width || original.height != reconstructed.height) {
        printf("[EvalMetrics] ERROR: Dimension mismatch (%ux%u vs %ux%u)\n",
               original.width, original.height, reconstructed.width, reconstructed.height);
        return result;
    }

    // Both HDR: use HDR-aware metrics directly.
    if (original.is_hdr && reconstructed.is_hdr) {
        result.psnr_db = compute_psnr_hdr_internal(original, reconstructed);
        result.ssim = compute_ssim_hdr_internal(original, reconstructed);
        result.flip = compute_flip_hdr_internal(original, reconstructed);
        result.lpips_approx = compute_lpips_hdr_internal(original, reconstructed);
        return result;
    }

    // Mismatch: original LDR but reconstructed HDR (e.g. BC6H/HDR ASTC on LDR source).
    // Tone-map reconstructed float -> uint8 with clamp [0,1] for fair comparison.
    if (!original.is_hdr && reconstructed.is_hdr) {
        TextureData tonemap;
        tonemap.width = reconstructed.width;
        tonemap.height = reconstructed.height;
        tonemap.channels = reconstructed.channels;
        tonemap.is_hdr = false;
        tonemap.format = TexelFormat::RGBA8_UNORM;
        size_t num = (size_t)reconstructed.width * reconstructed.height * reconstructed.channels;
        tonemap.pixels.resize(num);
        const float* src = reinterpret_cast<const float*>(reconstructed.pixels.data());
        for (size_t i = 0; i < num; i++) {
            float v = src[i];
            if (!std::isfinite(v)) v = 0.0f;
            if (v < 0.0f) v = 0.0f;
            if (v > 1.0f) v = 1.0f;
            tonemap.pixels[i] = (uint8_t)(v * 255.0f + 0.5f);
        }
        result.psnr_db = compute_psnr(original, tonemap);
        result.ssim = compute_ssim(original, tonemap);
        result.flip = compute_flip(original, tonemap);
        result.lpips_approx = compute_lpips_approx(original, tonemap);
        return result;
    }

    // Mismatch: original HDR but reconstructed LDR (LDR ASTC on HDR source).
    // This is an inherently bad combination: HDR data clamped to [0,1] LDR.
    // Tone-map original to uint8 too (so both are LDR uint8 and comparable).
    if (original.is_hdr && !reconstructed.is_hdr) {
        TextureData tonemap_orig;
        tonemap_orig.width = original.width;
        tonemap_orig.height = original.height;
        tonemap_orig.channels = original.channels;
        tonemap_orig.is_hdr = false;
        tonemap_orig.format = TexelFormat::RGBA8_UNORM;
        size_t num = (size_t)original.width * original.height * original.channels;
        tonemap_orig.pixels.resize(num);
        const float* src = reinterpret_cast<const float*>(original.pixels.data());
        for (size_t i = 0; i < num; i++) {
            float v = src[i];
            if (!std::isfinite(v)) v = 0.0f;
            if (v < 0.0f) v = 0.0f;
            if (v > 1.0f) v = 1.0f;
            tonemap_orig.pixels[i] = (uint8_t)(v * 255.0f + 0.5f);
        }
        result.psnr_db = compute_psnr(tonemap_orig, reconstructed);
        result.ssim = compute_ssim(tonemap_orig, reconstructed);
        result.flip = compute_flip(tonemap_orig, reconstructed);
        result.lpips_approx = compute_lpips_approx(tonemap_orig, reconstructed);
        return result;
    }

    // Both LDR: standard path.
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
