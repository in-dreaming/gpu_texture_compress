#pragma once

#include <SDL3/SDL_gpu.h>
#include <string>
#include <vector>
#include <cstdint>

namespace gtc {

enum class TexelFormat {
    RGBA8_UNORM,    // Standard LDR color/albedo
    RGBA8_SRGB,    // sRGB-encoded color
    RG8_UNORM,     // Normal maps (XY only)
    R8_UNORM,      // Single-channel (AO, roughness, metalness)
    RGBA16_FLOAT,  // HDR
    RGBA32_FLOAT,  // Full-precision HDR
};

struct TextureData {
    std::vector<uint8_t> pixels;   // Raw pixel data (CPU-side)
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t channels = 0;         // 1, 2, 3, or 4
    bool is_hdr = false;
    TexelFormat format = TexelFormat::RGBA8_UNORM;
    std::string source_path;

    // Size in bytes of pixel data
    size_t byte_size() const {
        size_t bpc = is_hdr ? sizeof(float) : sizeof(uint8_t);
        return (size_t)width * height * channels * bpc;
    }
};

struct GpuTexture {
    SDL_GPUTexture* texture = nullptr;
    uint32_t width = 0;
    uint32_t height = 0;
    SDL_GPUTextureFormat format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
};

class TextureLoader {
public:
    explicit TextureLoader(SDL_GPUDevice* device);

    // Load from disk into CPU memory (always loads as RGBA8 or RGBA32F for HDR)
    TextureData load_from_file(const std::string& path);

    // Upload CPU texture to GPU
    GpuTexture upload_to_gpu(const TextureData& data);

    // Download GPU texture back to CPU (for evaluation)
    TextureData download_from_gpu(const GpuTexture& gpu_tex);

    // Release a GPU texture
    void release(GpuTexture& tex);

    // Load test images from dataset directory
    struct TestImage {
        std::string name;
        std::string category;  // "color", "normal", "hdr", "single_channel"
        TextureData data;
    };
    std::vector<TestImage> load_test_dataset(const std::string& dataset_root);

    // Save RGBA8 image to PNG
    static bool save_png(const std::string& path, const std::vector<uint8_t>& rgba,
                         int width, int height);

private:
    SDL_GPUDevice* device_;

    // Determine category from file path
    static std::string categorize_path(const std::string& path);
};

} // namespace gtc
