#include "compression_pipeline.h"
#include <cstdio>
#include <chrono>

namespace gtc {

CompressionPipeline::CompressionPipeline(GpuDevice& device, ShaderCompiler& compiler,
                                         ComputeDispatch& dispatch, const std::string& shader_dir)
    : device_(device), compiler_(compiler), dispatch_(dispatch), shader_dir_(shader_dir) {}

std::string CompressionPipeline::shader_path_for_format(GtcFormat format) const {
    const auto& info = get_format_info(format);
    return shader_dir_ + "/" + info.shader_file;
}

bool CompressionPipeline::prepare_format(GtcFormat format) {
    std::string path = shader_path_for_format(format);
    const auto& info = get_format_info(format);

    printf("[Pipeline] Compiling shader for %s: %s\n", info.name, path.c_str());

    CompiledShader shader = compiler_.compile_compute(path, "MainCS");
    if (shader.bytecode.empty()) {
        printf("[Pipeline] ERROR: Failed to compile %s: %s\n",
               info.name, compiler_.get_last_error().c_str());
        return false;
    }

    // Resource binding layout:
    // - 1 texture sampler (SourceTexture + PointSampler) at binding 0
    // - 1 readwrite storage buffer (OutputBlocks) at binding 1
    // - Uniform data via push constants (not a descriptor binding)
    SDL_GPUComputePipeline* pipeline = dispatch_.create_pipeline(
        shader,
        /*num_samplers=*/1,
        /*num_readonly_storage_textures=*/0,
        /*num_readwrite_storage_textures=*/0,
        /*num_readonly_storage_buffers=*/0,
        /*num_readwrite_storage_buffers=*/1,
        /*num_uniform_buffers=*/1
    );

    if (!pipeline) {
        printf("[Pipeline] ERROR: Failed to create pipeline for %s\n", info.name);
        return false;
    }

    FormatPipeline fp;
    fp.pipeline = pipeline;
    fp.ready = true;
    pipelines_[(int)format] = fp;

    printf("[Pipeline] Ready: %s\n", info.name);
    return true;
}

CompressionResult CompressionPipeline::compress(const GpuTexture& source, GtcFormat format, int quality_level) {
    CompressionResult result;
    result.format = format;
    result.width = source.width;
    result.height = source.height;

    auto it = pipelines_.find((int)format);
    if (it == pipelines_.end() || !it->second.ready) {
        result.error_message = "Format not prepared: " + std::string(get_format_info(format).name);
        return result;
    }

    const auto& info = get_format_info(format);
    uint32_t blocks_x = (source.width + info.block_width - 1) / info.block_width;
    uint32_t blocks_y = (source.height + info.block_height - 1) / info.block_height;
    uint32_t total_blocks = blocks_x * blocks_y;
    uint32_t output_size = total_blocks * info.block_bytes;

    // Create output buffer
    SDL_GPUBuffer* output_buffer = dispatch_.create_buffer(
        output_size,
        SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE
    );
    if (!output_buffer) {
        result.error_message = "Failed to create output buffer";
        return result;
    }

    // Set up uniform data
    CompressParams params;
    params.TexWidth = (int32_t)source.width;
    params.TexHeight = (int32_t)source.height;
    params.BlocksX = (int32_t)blocks_x;
    params.BlocksY = (int32_t)blocks_y;
    params.QualityLevel = quality_level;
    params.Flags = 0;
    params.Pad0 = 0.0f;
    params.Pad1 = 0.0f;

    // Set up bindings
    ComputeBindings bindings;

    ComputeBindings::SamplerBinding tex_bind;
    tex_bind.texture = source.texture;
    tex_bind.sampler = dispatch_.create_point_sampler();
    bindings.texture_samplers.push_back(tex_bind);

    bindings.readwrite_storage_buffers.push_back(output_buffer);
    bindings.uniform_data = &params;
    bindings.uniform_size = sizeof(params);

    // Calculate dispatch dimensions
    DispatchDims dims = dispatch_.calc_dispatch(
        source.width, source.height,
        info.block_width, info.block_height,
        8, 8  // threadgroup size
    );

    // Dispatch and time it
    auto t0 = std::chrono::high_resolution_clock::now();
    bool ok = dispatch_.dispatch_sync(it->second.pipeline, bindings, dims);
    auto t1 = std::chrono::high_resolution_clock::now();

    if (!ok) {
        result.error_message = "Dispatch failed";
        SDL_ReleaseGPUBuffer(device_.device(), output_buffer);
        return result;
    }

    result.compression_time_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    // Download compressed data
    result.compressed_data.resize(output_size);
    if (!dispatch_.download_buffer(output_buffer, result.compressed_data.data(), output_size)) {
        result.error_message = "Failed to download compressed data";
        SDL_ReleaseGPUBuffer(device_.device(), output_buffer);
        return result;
    }

    SDL_ReleaseGPUBuffer(device_.device(), output_buffer);
    result.success = true;
    return result;
}

} // namespace gtc
