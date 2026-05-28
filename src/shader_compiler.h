#pragma once

#include <SDL3/SDL_gpu.h>
#include <string>
#include <vector>
#include <unordered_map>
#include <cstdint>

namespace gtc {

struct ShaderDefine {
    std::string name;
    std::string value;
};

struct CompiledShader {
    std::vector<uint8_t> bytecode;
    SDL_GPUShaderFormat format;
    std::string entry_point;
    uint32_t threadgroup_size[3] = {8, 8, 1};
};

class ShaderCompiler {
public:
    explicit ShaderCompiler(SDL_GPUDevice* device);

    // Compile HLSL compute shader to native bytecode
    // Uses SDL_shadercross if available, or pre-compiled SPIR-V
    CompiledShader compile_compute(
        const std::string& hlsl_path,
        const std::string& entry_point = "MainCS",
        const std::vector<ShaderDefine>& defines = {}
    );

    // Get last compilation error
    const std::string& get_last_error() const { return last_error_; }

    // Check if file was modified since last compile (for hot-reload)
    bool needs_recompile(const std::string& path) const;

private:
    SDL_GPUDevice* device_;
    std::string last_error_;
    std::unordered_map<std::string, uint64_t> file_mtimes_;

    // Read file contents
    std::string read_file(const std::string& path);

    // Prepend defines to HLSL source
    std::string prepend_defines(const std::string& source, const std::vector<ShaderDefine>& defines);
};

} // namespace gtc
