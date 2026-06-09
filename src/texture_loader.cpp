#include "texture_loader.h"
#include <SDL3/SDL.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <cstdio>
#include <algorithm>
#include <filesystem>

namespace fs = std::filesystem;

namespace gtc {

TextureLoader::TextureLoader(SDL_GPUDevice* device)
    : device_(device) {}

TextureData TextureLoader::load_from_file(const std::string& path) {
    TextureData data;

    // Normalize path separators for Windows
    std::string norm_path = path;
    for (auto& ch : norm_path) {
        if (ch == '/') ch = '\\';
    }
    data.source_path = norm_path;

    // Determine if HDR by extension (more reliable than stbi_is_hdr which opens the file)
    std::string lower_path = norm_path;
    std::transform(lower_path.begin(), lower_path.end(), lower_path.begin(), ::tolower);
    bool is_hdr_file = (lower_path.find(".hdr") != std::string::npos ||
                        lower_path.find(".exr") != std::string::npos);

    if (is_hdr_file) {
        int w, h, c;
        float* pixels = stbi_loadf(norm_path.c_str(), &w, &h, &c, 4);
        if (!pixels) {
            fprintf(stderr, "[TextureLoader] Failed to load HDR: %s (%s)\n",
                    norm_path.c_str(), stbi_failure_reason());
            return data;
        }
        data.width = (uint32_t)w;
        data.height = (uint32_t)h;
        data.channels = 4;
        data.is_hdr = true;
        data.format = TexelFormat::RGBA32_FLOAT;
        size_t byte_count = (size_t)w * h * 4 * sizeof(float);
        data.pixels.resize(byte_count);
        memcpy(data.pixels.data(), pixels, byte_count);
        stbi_image_free(pixels);
    } else {
        int w, h, c;
        stbi_uc* pixels = stbi_load(norm_path.c_str(), &w, &h, &c, 4);
        if (!pixels) {
            fprintf(stderr, "[TextureLoader] Failed to load: %s (%s)\n",
                    norm_path.c_str(), stbi_failure_reason());
            return data;
        }
        data.width = (uint32_t)w;
        data.height = (uint32_t)h;
        data.channels = 4;
        data.is_hdr = false;
        data.format = TexelFormat::RGBA8_UNORM;
        size_t byte_count = (size_t)w * h * 4;
        data.pixels.resize(byte_count);
        memcpy(data.pixels.data(), pixels, byte_count);
        stbi_image_free(pixels);
    }

    return data;
}

GpuTexture TextureLoader::upload_to_gpu(const TextureData& data) {
    GpuTexture result;
    if (data.pixels.empty()) return result;

    result.width = data.width;
    result.height = data.height;

    // Determine GPU format
    if (data.is_hdr) {
        result.format = SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT;
    } else {
        result.format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
    }

    // Create GPU texture
    SDL_GPUTextureCreateInfo tex_info = {};
    tex_info.type = SDL_GPU_TEXTURETYPE_2D;
    tex_info.format = result.format;
    tex_info.width = data.width;
    tex_info.height = data.height;
    tex_info.layer_count_or_depth = 1;
    tex_info.num_levels = 1;
    tex_info.usage = SDL_GPU_TEXTUREUSAGE_SAMPLER | SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_READ;

    result.texture = SDL_CreateGPUTexture(device_, &tex_info);
    if (!result.texture) {
        SDL_Log("Failed to create GPU texture: %s", SDL_GetError());
        return result;
    }

    // Create transfer buffer and upload
    SDL_GPUTransferBufferCreateInfo transfer_info = {};
    transfer_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
    transfer_info.size = (uint32_t)data.byte_size();

    SDL_GPUTransferBuffer* transfer_buf = SDL_CreateGPUTransferBuffer(device_, &transfer_info);
    if (!transfer_buf) {
        SDL_Log("Failed to create transfer buffer: %s", SDL_GetError());
        return result;
    }

    // Map and copy data
    void* mapped = SDL_MapGPUTransferBuffer(device_, transfer_buf, false);
    memcpy(mapped, data.pixels.data(), data.byte_size());
    SDL_UnmapGPUTransferBuffer(device_, transfer_buf);

    // Upload via command buffer
    SDL_GPUCommandBuffer* cmd = SDL_AcquireGPUCommandBuffer(device_);
    SDL_GPUCopyPass* copy_pass = SDL_BeginGPUCopyPass(cmd);

    SDL_GPUTextureTransferInfo src_info = {};
    src_info.transfer_buffer = transfer_buf;
    src_info.offset = 0;

    SDL_GPUTextureRegion dst_region = {};
    dst_region.texture = result.texture;
    dst_region.w = data.width;
    dst_region.h = data.height;
    dst_region.d = 1;

    SDL_UploadToGPUTexture(copy_pass, &src_info, &dst_region, false);
    SDL_EndGPUCopyPass(copy_pass);

    // Submit and wait
    SDL_GPUFence* fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    SDL_WaitForGPUFences(device_, true, &fence, 1);
    SDL_ReleaseGPUFence(device_, fence);
    SDL_ReleaseGPUTransferBuffer(device_, transfer_buf);

    return result;
}

TextureData TextureLoader::download_from_gpu(const GpuTexture& gpu_tex) {
    TextureData data;
    if (!gpu_tex.texture) return data;

    data.width = gpu_tex.width;
    data.height = gpu_tex.height;
    data.channels = 4;

    bool is_hdr = (gpu_tex.format == SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT ||
                   gpu_tex.format == SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT);
    data.is_hdr = is_hdr;
    data.format = is_hdr ? TexelFormat::RGBA32_FLOAT : TexelFormat::RGBA8_UNORM;

    size_t bpp = is_hdr ? 16 : 4; // bytes per pixel
    size_t byte_count = (size_t)data.width * data.height * bpp;
    data.pixels.resize(byte_count);

    // Create download transfer buffer
    SDL_GPUTransferBufferCreateInfo transfer_info = {};
    transfer_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD;
    transfer_info.size = (uint32_t)byte_count;

    SDL_GPUTransferBuffer* transfer_buf = SDL_CreateGPUTransferBuffer(device_, &transfer_info);
    if (!transfer_buf) {
        SDL_Log("Failed to create download transfer buffer: %s", SDL_GetError());
        return data;
    }

    // Download via command buffer
    SDL_GPUCommandBuffer* cmd = SDL_AcquireGPUCommandBuffer(device_);
    SDL_GPUCopyPass* copy_pass = SDL_BeginGPUCopyPass(cmd);

    SDL_GPUTextureRegion src_region = {};
    src_region.texture = gpu_tex.texture;
    src_region.w = data.width;
    src_region.h = data.height;
    src_region.d = 1;

    SDL_GPUTextureTransferInfo dst_info = {};
    dst_info.transfer_buffer = transfer_buf;
    dst_info.offset = 0;

    SDL_DownloadFromGPUTexture(copy_pass, &src_region, &dst_info);
    SDL_EndGPUCopyPass(copy_pass);

    SDL_GPUFence* fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    SDL_WaitForGPUFences(device_, true, &fence, 1);
    SDL_ReleaseGPUFence(device_, fence);

    // Map and copy back
    void* mapped = SDL_MapGPUTransferBuffer(device_, transfer_buf, false);
    memcpy(data.pixels.data(), mapped, byte_count);
    SDL_UnmapGPUTransferBuffer(device_, transfer_buf);

    SDL_ReleaseGPUTransferBuffer(device_, transfer_buf);
    return data;
}

void TextureLoader::release(GpuTexture& tex) {
    if (tex.texture) {
        SDL_ReleaseGPUTexture(device_, tex.texture);
        tex.texture = nullptr;
    }
}

std::string TextureLoader::categorize_path(const std::string& path) {
    std::string lower = path;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);

    if (lower.find("normal") != std::string::npos || lower.find("_nor_") != std::string::npos)
        return "normal";
    if (lower.find("hdr") != std::string::npos || lower.find(".exr") != std::string::npos ||
        lower.find(".hdr") != std::string::npos)
        return "hdr";
    if (lower.find("roughness") != std::string::npos || lower.find("metalness") != std::string::npos ||
        lower.find("ambient") != std::string::npos || lower.find("displacement") != std::string::npos ||
        lower.find("ldr-l") != std::string::npos)
        return "single_channel";
    return "color";
}

std::vector<TextureLoader::TestImage> TextureLoader::load_test_dataset(const std::string& dataset_root) {
    std::vector<TestImage> images;

    // Supported extensions
    std::vector<std::string> extensions = {".png", ".jpg", ".jpeg", ".hdr", ".exr"};

    for (auto& entry : fs::recursive_directory_iterator(dataset_root)) {
        if (!entry.is_regular_file()) continue;

        std::string ext = entry.path().extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

        bool supported = false;
        for (auto& e : extensions) {
            if (ext == e) { supported = true; break; }
        }
        if (!supported) continue;

        std::string path = entry.path().string();
        TestImage img;
        img.name = entry.path().filename().string();
        img.category = categorize_path(path);
        img.data = load_from_file(path);

        if (img.data.width > 0 && img.data.height > 0) {
            images.push_back(std::move(img));
        }
    }

    printf("Loaded %zu test images from %s\n", images.size(), dataset_root.c_str());
    return images;
}

bool TextureLoader::save_png(const std::string& path, const std::vector<uint8_t>& rgba,
                             int width, int height) {
    return stbi_write_png(path.c_str(), width, height, 4, rgba.data(), width * 4) != 0;
}

} // namespace gtc
