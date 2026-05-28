#include "gpu_device.h"
#include <cstdio>

namespace gtc {

GpuDevice::~GpuDevice() {
    shutdown();
}

bool GpuDevice::init(const char* preferred_backend) {
    if (initialized_) return true;

    // Initialize SDL - try with video first, fallback to headless
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "[GPU] SDL video init failed: %s, trying headless\n", SDL_GetError());
        if (!SDL_Init(0)) {
            fprintf(stderr, "[GPU] SDL headless init failed: %s\n", SDL_GetError());
            return false;
        }
    }

    // Determine shader formats to request
    // We use SPIRV (compiled by system DXC from Vulkan SDK)
    SDL_GPUShaderFormat shader_formats = SDL_GPU_SHADERFORMAT_SPIRV;

    // Prefer Vulkan backend since our pipeline produces SPIRV
    // Disable debug mode to avoid validation layer noise during experiments
    const char* backend = preferred_backend ? preferred_backend : "vulkan";

    // Create GPU device (debug=false to skip validation layers)
    device_ = SDL_CreateGPUDevice(shader_formats, false, backend);
    if (!device_) {
        // Fallback: try any available backend
        device_ = SDL_CreateGPUDevice(shader_formats, false, nullptr);
    }
    if (!device_) {
        fprintf(stderr, "[GPU] Failed to create GPU device: %s\n", SDL_GetError());
        SDL_Quit();
        return false;
    }

    // Query device info
    const char* driver = SDL_GetGPUDeviceDriver(device_);
    info_.driver_name = driver ? driver : "unknown";
    info_.device_name = info_.driver_name;
    info_.supports_compute = true;

    initialized_ = true;
    return true;
}

void GpuDevice::shutdown() {
    if (!initialized_) return;

    if (device_) {
        SDL_DestroyGPUDevice(device_);
        device_ = nullptr;
    }

    SDL_Quit();
    initialized_ = false;
}

bool GpuDevice::submit_and_wait(SDL_GPUCommandBuffer* cmd_buf) {
    SDL_GPUFence* fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd_buf);
    if (!fence) {
        SDL_Log("Failed to submit command buffer: %s", SDL_GetError());
        return false;
    }

    SDL_WaitForGPUFences(device_, true, &fence, 1);
    SDL_ReleaseGPUFence(device_, fence);
    return true;
}

void GpuDevice::print_info() const {
    printf("=== GPU Device Info ===\n");
    printf("  Driver:   %s\n", info_.driver_name.c_str());
    printf("  Compute:  %s\n", info_.supports_compute ? "supported" : "NOT supported");
    printf("=======================\n");
    fflush(stdout);
}

} // namespace gtc
