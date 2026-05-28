#pragma once

#include <SDL3/SDL_gpu.h>
#include "shader_compiler.h"
#include <vector>
#include <cstdint>

namespace gtc {

struct ComputeBindings {
    // Read-only sampled texture
    struct SamplerBinding {
        SDL_GPUTexture* texture = nullptr;
        SDL_GPUSampler* sampler = nullptr;
    };
    std::vector<SamplerBinding> texture_samplers;

    // Read-only storage textures (no sampler)
    std::vector<SDL_GPUTexture*> readonly_storage_textures;

    // Read-write storage textures
    std::vector<SDL_GPUTexture*> readwrite_storage_textures;

    // Read-only storage buffers
    std::vector<SDL_GPUBuffer*> readonly_storage_buffers;

    // Read-write storage buffers
    std::vector<SDL_GPUBuffer*> readwrite_storage_buffers;

    // Uniform data (pushed via SDL_PushGPUComputeUniformData)
    const void* uniform_data = nullptr;
    uint32_t uniform_size = 0;
};

struct DispatchDims {
    uint32_t group_count_x = 1;
    uint32_t group_count_y = 1;
    uint32_t group_count_z = 1;
};

class ComputeDispatch {
public:
    explicit ComputeDispatch(SDL_GPUDevice* device);
    ~ComputeDispatch();

    // Create a compute pipeline from compiled HLSL source
    // Uses SDL_ShaderCross under the hood
    SDL_GPUComputePipeline* create_pipeline(
        const CompiledShader& shader,
        uint32_t num_samplers,
        uint32_t num_readonly_storage_textures,
        uint32_t num_readwrite_storage_textures,
        uint32_t num_readonly_storage_buffers,
        uint32_t num_readwrite_storage_buffers,
        uint32_t num_uniform_buffers
    );

    // Calculate dispatch dimensions for block-based compression
    DispatchDims calc_dispatch(
        uint32_t image_width, uint32_t image_height,
        uint32_t block_dim_x, uint32_t block_dim_y,
        uint32_t threadgroup_x = 8, uint32_t threadgroup_y = 8
    );

    // Execute compute pass synchronously (submit + wait)
    bool dispatch_sync(
        SDL_GPUComputePipeline* pipeline,
        const ComputeBindings& bindings,
        const DispatchDims& dims
    );

    // Create a GPU buffer
    SDL_GPUBuffer* create_buffer(uint32_t size_bytes, SDL_GPUBufferUsageFlags usage);

    // Create a sampler (point/linear)
    SDL_GPUSampler* create_point_sampler();

    // Download buffer data to CPU
    bool download_buffer(SDL_GPUBuffer* buffer, void* dst, uint32_t size_bytes);

private:
    SDL_GPUDevice* device_;
    SDL_GPUSampler* point_sampler_ = nullptr;
};

} // namespace gtc
