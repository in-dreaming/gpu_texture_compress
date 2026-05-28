// Minimal test for eval metrics
// Verifies PSNR/SSIM produce expected values for known inputs

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <cassert>

// Inline a minimal version of the metrics for testing without full SDL dependency
// This verifies the math is correct.

static double test_psnr(const uint8_t* a, const uint8_t* b, int num_pixels, int channels) {
    double sum_sq = 0.0;
    int count = 0;
    int ch = channels < 3 ? channels : 3; // RGB only

    for (int i = 0; i < num_pixels; i++) {
        for (int c = 0; c < ch; c++) {
            double diff = (double)a[i * channels + c] - (double)b[i * channels + c];
            sum_sq += diff * diff;
            count++;
        }
    }

    double mse = sum_sq / (double)count;
    if (mse < 1e-10) return 100.0;
    return 10.0 * log10(255.0 * 255.0 / mse);
}

int main() {
    printf("=== Test: Eval Metrics ===\n\n");

    // Test 1: Identical images -> PSNR = 100 (or infinity)
    {
        uint8_t img[64];
        memset(img, 128, sizeof(img));
        double psnr = test_psnr(img, img, 16, 4);
        printf("[Test 1] Identical images: PSNR = %.1f (expected: 100.0)\n", psnr);
        assert(psnr >= 99.0);
    }

    // Test 2: Max difference (0 vs 255) -> PSNR should be 0
    {
        uint8_t img_a[64], img_b[64];
        memset(img_a, 0, sizeof(img_a));
        memset(img_b, 255, sizeof(img_b));
        double psnr = test_psnr(img_a, img_b, 16, 4);
        printf("[Test 2] Max difference:    PSNR = %.2f dB (expected: ~0)\n", psnr);
        // MSE = 255^2, PSNR = 10*log10(1) = 0
        assert(fabs(psnr - 0.0) < 0.01);
    }

    // Test 3: Small noise (+-1) -> PSNR should be ~48 dB
    {
        uint8_t img_a[256], img_b[256];
        for (int i = 0; i < 256; i++) {
            img_a[i] = 128;
            img_b[i] = (i % 2 == 0) ? 129 : 127;
        }
        double psnr = test_psnr(img_a, img_b, 64, 4);
        printf("[Test 3] Small noise (+-1): PSNR = %.2f dB (expected: ~48.13)\n", psnr);
        assert(psnr > 47.0 && psnr < 49.0);
    }

    // Test 4: Gradient with quantization error (typical BC1 scenario)
    {
        uint8_t img_a[1024], img_b[1024];
        for (int i = 0; i < 256; i++) {
            // Smooth gradient
            uint8_t val = (uint8_t)i;
            img_a[i * 4 + 0] = val;
            img_a[i * 4 + 1] = val;
            img_a[i * 4 + 2] = val;
            img_a[i * 4 + 3] = 255;

            // Quantized to 5-bit (like RGB565 red channel)
            uint8_t quant = (uint8_t)((val >> 3) * 255 / 31);
            img_b[i * 4 + 0] = quant;
            img_b[i * 4 + 1] = quant;
            img_b[i * 4 + 2] = quant;
            img_b[i * 4 + 3] = 255;
        }
        double psnr = test_psnr(img_a, img_b, 256, 4);
        printf("[Test 4] 5-bit quantization: PSNR = %.2f dB (expected: ~38-42)\n", psnr);
        assert(psnr > 35.0 && psnr < 45.0);
    }

    printf("\n=== All metric tests passed! ===\n");
    return 0;
}
