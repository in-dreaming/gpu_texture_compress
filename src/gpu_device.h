#pragma once

#include <SDL3/SDL.h>
#include <SDL3/SDL_gpu.h>
#include <string>
#include <cstdint>

namespace gtc {

struct DeviceInfo {
    std::string driver_name;     // "vulkan", "d3d12", "metal"
    std::string device_name;     // GPU name
    bool supports_compute;
};

class GpuDevice {
public:
    GpuDevice() = default;
    ~GpuDevice();

    // Initialize SDL and create GPU device
    // preferred_backend: "vulkan", "d3d12", "metal", or nullptr for auto
    bool init(const char* preferred_backend = nullptr);
    void shutdown();

    SDL_GPUDevice* device() const { return device_; }
    const DeviceInfo& info() const { return info_; }

    // Submit a command buffer and wait for completion (synchronous)
    bool submit_and_wait(SDL_GPUCommandBuffer* cmd_buf);

    // Print device info to stdout
    void print_info() const;

    // Non-copyable
    GpuDevice(const GpuDevice&) = delete;
    GpuDevice& operator=(const GpuDevice&) = delete;

private:
    SDL_GPUDevice* device_ = nullptr;
    DeviceInfo info_;
    bool initialized_ = false;
};

} // namespace gtc
