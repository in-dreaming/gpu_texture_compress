#include "shader_compiler.h"
#include <SDL3/SDL.h>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <cstdio>
#include <cstdlib>
#include <array>

namespace gtc {

ShaderCompiler::ShaderCompiler(SDL_GPUDevice* device)
    : device_(device) {}

std::string ShaderCompiler::read_file(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        last_error_ = "Cannot open file: " + path;
        return "";
    }
    std::stringstream ss;
    ss << file.rdbuf();
    return ss.str();
}

std::string ShaderCompiler::prepend_defines(const std::string& source,
                                            const std::vector<ShaderDefine>& defines) {
    if (defines.empty()) return source;

    std::string header;
    for (auto& def : defines) {
        header += "#define " + def.name + " " + def.value + "\n";
    }
    return header + source;
}

// Find dxc.exe on the system (prefer Vulkan SDK's DXC which has SPIRV support)
static std::string find_dxc() {
    // Priority order: Vulkan SDK (has SPIRV) > PATH > Windows SDK (no SPIRV)

    // 1. Check VULKAN_SDK environment variable
    const char* vulkan_sdk = std::getenv("VULKAN_SDK");
    if (vulkan_sdk) {
        std::string vk_dxc = std::string(vulkan_sdk) + "/Bin/dxc.exe";
        if (std::filesystem::exists(vk_dxc)) return vk_dxc;
    }

    // 2. Common Vulkan SDK locations
    const char* vk_candidates[] = {
        "C:/VulkanSDK/1.4.328.1/Bin/dxc.exe",
        "C:/VulkanSDK/1.3.296.0/Bin/dxc.exe",
        "C:/VulkanSDK/1.3.290.0/Bin/dxc.exe",
        "C:/VulkanSDK/1.3.280.0/Bin/dxc.exe",
    };
    for (auto& path : vk_candidates) {
        if (std::filesystem::exists(path)) return path;
    }

    // 3. Try "where dxc" on Windows (may find VulkanSDK in PATH)
    FILE* pipe = _popen("where dxc.exe 2>nul", "r");
    if (pipe) {
        char buf[512];
        if (fgets(buf, sizeof(buf), pipe)) {
            _pclose(pipe);
            std::string result(buf);
            while (!result.empty() && (result.back() == '\n' || result.back() == '\r'))
                result.pop_back();
            if (!result.empty()) return result;
        } else {
            _pclose(pipe);
        }
    }

    return "";
}

CompiledShader ShaderCompiler::compile_compute(
    const std::string& hlsl_path,
    const std::string& entry_point,
    const std::vector<ShaderDefine>& defines)
{
    CompiledShader result;
    result.entry_point = entry_point;
    last_error_.clear();

    // Verify source file exists
    if (!std::filesystem::exists(hlsl_path)) {
        last_error_ = "Shader file not found: " + hlsl_path;
        return result;
    }

    // Find DXC compiler
    static std::string dxc_path = find_dxc();
    if (dxc_path.empty()) {
        last_error_ = "Cannot find dxc.exe. Install Windows SDK or add dxc to PATH.";
        printf("[ShaderCompiler] ERROR: %s\n", last_error_.c_str());
        return result;
    }

    // Get include path — use the shader root directory (parent of dispatch/)
    // so that #include "common/..." and #include "compress/..." work correctly
    std::filesystem::path shader_path(hlsl_path);
    std::string parent_dir = shader_path.parent_path().string();
    // If shader is in a subdirectory (dispatch/), go up one level to get root
    std::string include_dir = shader_path.parent_path().parent_path().string();
    if (include_dir.empty() || include_dir == parent_dir) {
        include_dir = parent_dir; // Fallback: use same directory
    }

    // Generate output path (temp file for SPIRV)
    std::string spirv_output = hlsl_path + ".spv";

    // Build DXC command line:
    // dxc -T cs_6_0 -E MainCS -spirv -I <include_dir> [-D defines...] -Fo output.spv input.hlsl
    // On Windows, _popen needs cmd /c wrapping when paths have spaces
    //
    // SDL3 GPU Vulkan backend uses MULTIPLE descriptor sets for compute:
    //   Set 0: Read-only resources (samplers, readonly storage textures, readonly storage buffers)
    //   Set 1: Read-write resources (RW storage textures, RW storage buffers)
    //   Set 2: Uniform buffers
    //
    // Within each set, bindings start from 0:
    //   Set 0, Binding 0: combined image/sampler (SourceTexture + PointSampler)
    //   Set 1, Binding 0: RW storage buffer (OutputBlocks)
    //   Set 2, Binding 0: uniform buffer (GtcParams / CompressParams)
    //
    // DXC -fvk-bind-register maps HLSL registers to specific (binding, set) pairs:
    //   register(t0) space0 → binding 0, set 0
    //   register(s0) space0 → binding 0, set 0 (combined)
    //   register(u0) space0 → binding 0, set 1
    //   register(b0) space0 → binding 0, set 2
    std::string inner_cmd = "\"" + dxc_path + "\"";
    inner_cmd += " -T cs_6_0";
    inner_cmd += " -E " + entry_point;
    inner_cmd += " -spirv";
    inner_cmd += " -fspv-target-env=vulkan1.1";
    inner_cmd += " -fvk-bind-register t0 0 0 0";  // t0 space0 → binding 0, set 0
    inner_cmd += " -fvk-bind-register s0 0 0 0";  // s0 space0 → binding 0, set 0
    inner_cmd += " -fvk-bind-register u0 0 0 1";  // u0 space0 → binding 0, set 1
    inner_cmd += " -fvk-bind-register b0 0 0 2";  // b0 space0 → binding 0, set 2
    inner_cmd += " -I \"" + include_dir + "\"";

    // Add defines
    for (auto& def : defines) {
        inner_cmd += " -D " + def.name;
        if (!def.value.empty()) inner_cmd += "=" + def.value;
    }

    inner_cmd += " -Fo \"" + spirv_output + "\"";
    inner_cmd += " \"" + hlsl_path + "\"";
    inner_cmd += " 2>&1";

    // Wrap with cmd /c for proper Windows path handling
    std::string cmd = "cmd /c \"" + inner_cmd + "\"";

    // Execute DXC
    printf("[ShaderCompiler] Running: %s\n", cmd.c_str());
    FILE* pipe = _popen(cmd.c_str(), "r");
    if (!pipe) {
        last_error_ = "Failed to execute dxc.exe";
        return result;
    }

    // Capture output (errors/warnings)
    std::string dxc_output;
    char buf[512];
    while (fgets(buf, sizeof(buf), pipe)) {
        dxc_output += buf;
    }
    int exit_code = _pclose(pipe);

    if (exit_code != 0) {
        last_error_ = "DXC compilation failed:\n" + dxc_output;
        printf("[ShaderCompiler] ERROR: %s\n", last_error_.c_str());
        // Clean up temp file
        std::filesystem::remove(spirv_output);
        return result;
    }

    if (!dxc_output.empty()) {
        printf("[ShaderCompiler] DXC warnings: %s\n", dxc_output.c_str());
    }

    // Read the SPIRV output file
    std::ifstream spirv_file(spirv_output, std::ios::binary | std::ios::ate);
    if (!spirv_file.is_open()) {
        last_error_ = "DXC produced no output file";
        return result;
    }

    size_t spirv_size = (size_t)spirv_file.tellg();
    spirv_file.seekg(0);
    result.bytecode.resize(spirv_size);
    spirv_file.read((char*)result.bytecode.data(), spirv_size);
    spirv_file.close();

    // Clean up temp SPIRV file
    std::filesystem::remove(spirv_output);

    result.format = SDL_GPU_SHADERFORMAT_SPIRV;

    // Update mtime tracking
    try {
        auto mtime = std::filesystem::last_write_time(hlsl_path);
        file_mtimes_[hlsl_path] = mtime.time_since_epoch().count();
    } catch (...) {}

    printf("[ShaderCompiler] Compiled: %s -> %zu bytes SPIRV\n",
           hlsl_path.c_str(), result.bytecode.size());

    return result;
}

bool ShaderCompiler::needs_recompile(const std::string& path) const {
    auto it = file_mtimes_.find(path);
    if (it == file_mtimes_.end()) return true;

    try {
        auto current_mtime = std::filesystem::last_write_time(path);
        return current_mtime.time_since_epoch().count() != it->second;
    } catch (...) {
        return true;
    }
}

} // namespace gtc
