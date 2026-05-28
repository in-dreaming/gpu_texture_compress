#include "compute_dispatch.h"
#include <SDL3/SDL.h>
#include <cstdio>
#include <cstring>

namespace gtc {

ComputeDispatch::ComputeDispatch(SDL_GPUDevice* device)
    : device_(device) {}

ComputeDispatch::~ComputeDispatch() {
    if (point_sampler_) {
        SDL_ReleaseGPUSampler(device_, point_sampler_);
        point_sampler_ = nullptr;
    }
}

SDL_GPUComputePipeline* ComputeDispatch::create_pipeline(
    const CompiledShader& shader,
    uint32_t num_samplers,
    uint32_t num_readonly_storage_textures,
    uint32_t num_readwrite_storage_textures,
    uint32_t num_readonly_storage_buffers,
    uint32_t num_readwrite_storage_buffers,
    uint32_t num_uniform_buffers)
{
    if (shader.bytecode.empty()) {
        SDL_Log("Cannot create pipeline: empty shader bytecode");
        return nullptr;
    }

    // Create pipeline directly from SPIRV bytecode with known resource layout.
    // We specify resource counts explicitly rather than relying on reflection,
    // because our shader interface is fixed and well-defined.
    SDL_GPUComputePipelineCreateInfo pipeline_info = {};
    pipeline_info.code = shader.bytecode.data();
    pipeline_info.code_size = shader.bytecode.size();
    pipeline_info.entrypoint = shader.entry_point.c_str();
    pipeline_info.format = SDL_GPU_SHADERFORMAT_SPIRV;
    pipeline_info.num_samplers = num_samplers;
    pipeline_info.num_readonly_storage_textures = num_readonly_storage_textures;
    pipeline_info.num_readonly_storage_buffers = num_readonly_storage_buffers;
    pipeline_info.num_readwrite_storage_textures = num_readwrite_storage_textures;
    pipeline_info.num_readwrite_storage_buffers = num_readwrite_storage_buffers;
    pipeline_info.num_uniform_buffers = num_uniform_buffers;
    pipeline_info.threadcount_x = shader.threadgroup_size[0];
    pipeline_info.threadcount_y = shader.threadgroup_size[1];
    pipeline_info.threadcount_z = shader.threadgroup_size[2];
    pipeline_info.props = 0;

    SDL_GPUComputePipeline* pipeline = SDL_CreateGPUComputePipeline(device_, &pipeline_info);
    if (!pipeline) {
        SDL_Log("Failed to create compute pipeline: %s", SDL_GetError());
    }

    return pipeline;
}

DispatchDims ComputeDispatch::calc_dispatch(
    uint32_t image_width, uint32_t image_height,
    uint32_t block_dim_x, uint32_t block_dim_y,
    uint32_t threadgroup_x, uint32_t threadgroup_y)
{
    uint32_t blocks_x = (image_width + block_dim_x - 1) / block_dim_x;
    uint32_t blocks_y = (image_height + block_dim_y - 1) / block_dim_y;

    DispatchDims dims;
    dims.group_count_x = (blocks_x + threadgroup_x - 1) / threadgroup_x;
    dims.group_count_y = (blocks_y + threadgroup_y - 1) / threadgroup_y;
    dims.group_count_z = 1;
    return dims;
}

bool ComputeDispatch::dispatch_sync(
    SDL_GPUComputePipeline* pipeline,
    const ComputeBindings& bindings,
    const DispatchDims& dims)
{
    SDL_GPUCommandBuffer* cmd = SDL_AcquireGPUCommandBuffer(device_);
    if (!cmd) {
        SDL_Log("Failed to acquire command buffer: %s", SDL_GetError());
        return false;
    }

    // Build binding arrays for SDL
    SDL_GPUStorageBufferReadWriteBinding* rw_buffer_bindings = nullptr;
    std::vector<SDL_GPUStorageBufferReadWriteBinding> rw_buf_bind_vec;
    if (!bindings.readwrite_storage_buffers.empty()) {
        rw_buf_bind_vec.resize(bindings.readwrite_storage_buffers.size());
        for (size_t i = 0; i < bindings.readwrite_storage_buffers.size(); i++) {
            rw_buf_bind_vec[i] = {};
            rw_buf_bind_vec[i].buffer = bindings.readwrite_storage_buffers[i];
        }
        rw_buffer_bindings = rw_buf_bind_vec.data();
    }

    SDL_GPUStorageTextureReadWriteBinding* rw_tex_bindings = nullptr;
    std::vector<SDL_GPUStorageTextureReadWriteBinding> rw_tex_bind_vec;
    if (!bindings.readwrite_storage_textures.empty()) {
        rw_tex_bind_vec.resize(bindings.readwrite_storage_textures.size());
        for (size_t i = 0; i < bindings.readwrite_storage_textures.size(); i++) {
            rw_tex_bind_vec[i] = {};
            rw_tex_bind_vec[i].texture = bindings.readwrite_storage_textures[i];
        }
        rw_tex_bindings = rw_tex_bind_vec.data();
    }

    // Begin compute pass
    SDL_GPUComputePass* pass = SDL_BeginGPUComputePass(
        cmd,
        rw_tex_bindings,
        (uint32_t)rw_tex_bind_vec.size(),
        rw_buffer_bindings,
        (uint32_t)rw_buf_bind_vec.size()
    );

    if (!pass) {
        SDL_Log("Failed to begin compute pass: %s", SDL_GetError());
        return false;
    }

    SDL_BindGPUComputePipeline(pass, pipeline);

    // Bind texture samplers
    if (!bindings.texture_samplers.empty()) {
        std::vector<SDL_GPUTextureSamplerBinding> sampler_binds(bindings.texture_samplers.size());
        for (size_t i = 0; i < bindings.texture_samplers.size(); i++) {
            sampler_binds[i] = {};
            sampler_binds[i].texture = bindings.texture_samplers[i].texture;
            sampler_binds[i].sampler = bindings.texture_samplers[i].sampler;
        }
        SDL_BindGPUComputeSamplers(pass, 0, sampler_binds.data(), (uint32_t)sampler_binds.size());
    }

    // Bind readonly storage textures
    if (!bindings.readonly_storage_textures.empty()) {
        SDL_BindGPUComputeStorageTextures(pass, 0,
            bindings.readonly_storage_textures.data(),
            (uint32_t)bindings.readonly_storage_textures.size());
    }

    // Bind readonly storage buffers
    if (!bindings.readonly_storage_buffers.empty()) {
        SDL_BindGPUComputeStorageBuffers(pass, 0,
            bindings.readonly_storage_buffers.data(),
            (uint32_t)bindings.readonly_storage_buffers.size());
    }

    // Push uniform data
    if (bindings.uniform_data && bindings.uniform_size > 0) {
        SDL_PushGPUComputeUniformData(cmd, 0, bindings.uniform_data, bindings.uniform_size);
    }

    // Dispatch
    SDL_DispatchGPUCompute(pass, dims.group_count_x, dims.group_count_y, dims.group_count_z);
    SDL_EndGPUComputePass(pass);

    // Submit and wait
    SDL_GPUFence* fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    if (!fence) {
        SDL_Log("Failed to submit command buffer: %s", SDL_GetError());
        return false;
    }
    SDL_WaitForGPUFences(device_, true, &fence, 1);
    SDL_ReleaseGPUFence(device_, fence);

    return true;
}

SDL_GPUBuffer* ComputeDispatch::create_buffer(uint32_t size_bytes, SDL_GPUBufferUsageFlags usage) {
    SDL_GPUBufferCreateInfo info = {};
    info.usage = usage;
    info.size = size_bytes;

    SDL_GPUBuffer* buffer = SDL_CreateGPUBuffer(device_, &info);
    if (!buffer) {
        SDL_Log("Failed to create GPU buffer (%u bytes): %s", size_bytes, SDL_GetError());
    }
    return buffer;
}

SDL_GPUSampler* ComputeDispatch::create_point_sampler() {
    if (point_sampler_) return point_sampler_;

    SDL_GPUSamplerCreateInfo info = {};
    info.min_filter = SDL_GPU_FILTER_NEAREST;
    info.mag_filter = SDL_GPU_FILTER_NEAREST;
    info.mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
    info.address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    info.address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    info.address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;

    point_sampler_ = SDL_CreateGPUSampler(device_, &info);
    if (!point_sampler_) {
        SDL_Log("Failed to create point sampler: %s", SDL_GetError());
    }
    return point_sampler_;
}

bool ComputeDispatch::download_buffer(SDL_GPUBuffer* buffer, void* dst, uint32_t size_bytes) {
    // Create download transfer buffer
    SDL_GPUTransferBufferCreateInfo transfer_info = {};
    transfer_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD;
    transfer_info.size = size_bytes;

    SDL_GPUTransferBuffer* transfer_buf = SDL_CreateGPUTransferBuffer(device_, &transfer_info);
    if (!transfer_buf) {
        SDL_Log("Failed to create download transfer buffer: %s", SDL_GetError());
        return false;
    }

    // Copy from GPU buffer to transfer buffer
    SDL_GPUCommandBuffer* cmd = SDL_AcquireGPUCommandBuffer(device_);
    SDL_GPUCopyPass* copy_pass = SDL_BeginGPUCopyPass(cmd);

    SDL_GPUBufferRegion src_region = {};
    src_region.buffer = buffer;
    src_region.offset = 0;
    src_region.size = size_bytes;

    SDL_GPUTransferBufferLocation dst_location = {};
    dst_location.transfer_buffer = transfer_buf;
    dst_location.offset = 0;

    SDL_DownloadFromGPUBuffer(copy_pass, &src_region, &dst_location);
    SDL_EndGPUCopyPass(copy_pass);

    SDL_GPUFence* fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    SDL_WaitForGPUFences(device_, true, &fence, 1);
    SDL_ReleaseGPUFence(device_, fence);

    // Map transfer buffer and copy to CPU
    void* mapped = SDL_MapGPUTransferBuffer(device_, transfer_buf, false);
    memcpy(dst, mapped, size_bytes);
    SDL_UnmapGPUTransferBuffer(device_, transfer_buf);

    SDL_ReleaseGPUTransferBuffer(device_, transfer_buf);
    return true;
}

} // namespace gtc
