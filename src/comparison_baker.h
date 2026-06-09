#pragma once

#include "compression_pipeline.h"
#include "decompressor.h"
#include "texture_loader.h"
#include "../sdk/include/gtc_formats.h"
#include <string>
#include <vector>

namespace gtc {

struct BakeConfig {
    std::string output_path = "comparison_atlas.png";
    std::string layout_path;  // optional sidecar; defaults to output_path + ".layout.txt"
    int thumb_size = 256;
    int quality_level = 1;
    bool include_hdr_formats = true;
    bool include_ldr_formats = true;
};

struct BakeResult {
    bool success = false;
    std::string error_message;
    int num_textures = 0;
    int num_formats = 0;
    int atlas_width = 0;
    int atlas_height = 0;
    double total_time_seconds = 0.0;
};

class ComparisonBaker {
public:
    ComparisonBaker(GpuDevice& device, ShaderCompiler& compiler,
                    ComputeDispatch& dispatch, const std::string& shader_dir,
                    const std::string& data_root);

    BakeResult bake(const BakeConfig& config);

private:
    struct BakeSection {
        std::string title;
        std::string category;
        std::vector<GtcFormat> formats;
    };

    GpuDevice& device_;
    ShaderCompiler& compiler_;
    ComputeDispatch& dispatch_;
    TextureLoader loader_;
    CompressionPipeline pipeline_;
    Decompressor decompressor_;
    std::string data_root_;

    static std::vector<BakeSection> build_sections(const BakeConfig& config);
    static bool texture_matches_section(const TextureLoader::TestImage& img, const BakeSection& section);
    static bool write_layout_file(const std::string& path, int thumb_size,
                                  const std::vector<BakeSection>& sections,
                                  const std::vector<std::vector<std::string>>& section_tex_names,
                                  int atlas_width, int atlas_height);
};

} // namespace gtc
