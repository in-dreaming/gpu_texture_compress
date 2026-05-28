#pragma once

#include "gpu_device.h"
#include "texture_loader.h"
#include "shader_compiler.h"
#include "compute_dispatch.h"
#include "shared_types.h"
#include "../sdk/include/gtc_formats.h"
#include <string>
#include <vector>
#include <unordered_map>

namespace gtc {

struct CompressionResult {
    std::vector<uint8_t> compressed_data; // Raw block data
    uint32_t width = 0;
    uint32_t height = 0;
    GtcFormat format = GTC_FORMAT_BC1;
    double compression_time_ms = 0.0;     // GPU time only
    bool success = false;
    std::string error_message;
};

class CompressionPipeline {
public:
    CompressionPipeline(GpuDevice& device, ShaderCompiler& compiler,
                        ComputeDispatch& dispatch, const std::string& shader_dir);

    // Prepare (compile) a compression shader for a given format
    bool prepare_format(GtcFormat format);

    // Run compression on a source texture (already on GPU)
    CompressionResult compress(const GpuTexture& source, GtcFormat format, int quality_level = 1);

    // Get the shader path for a format
    std::string shader_path_for_format(GtcFormat format) const;

private:
    GpuDevice& device_;
    ShaderCompiler& compiler_;
    ComputeDispatch& dispatch_;
    std::string shader_dir_;

    struct FormatPipeline {
        SDL_GPUComputePipeline* pipeline = nullptr;
        bool ready = false;
    };
    std::unordered_map<int, FormatPipeline> pipelines_;
};

} // namespace gtc
