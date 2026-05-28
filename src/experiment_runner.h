#pragma once

#include "compression_pipeline.h"
#include "decompressor.h"
#include "eval_metrics.h"
#include "texture_loader.h"
#include "../sdk/include/gtc_formats.h"
#include <string>
#include <vector>

namespace gtc {

struct ExperimentConfig {
    std::string name = "default";
    std::vector<GtcFormat> formats;
    std::vector<std::string> texture_paths;
    int quality_level = 1;
    int warmup_runs = 1;
    int measurement_runs = 3;
};

struct FormatResult {
    GtcFormat format;
    MetricsResult metrics;
    double compression_time_ms = 0.0;
    bool success = false;
    std::string error;
};

struct ExperimentResult {
    std::string experiment_name;
    double total_time_seconds = 0.0;
    bool success = false;
    std::string error_message;

    // Per-format aggregated metrics
    struct FormatAggregate {
        GtcFormat format;
        double avg_psnr = 0.0;
        double avg_ssim = 0.0;
        double avg_flip = 0.0;
        double avg_lpips = 0.0;
        double avg_time_ms = 0.0;
        int num_textures = 0;
    };
    std::vector<FormatAggregate> format_aggregates;
};

class ExperimentRunner {
public:
    ExperimentRunner(GpuDevice& device, ShaderCompiler& compiler,
                     ComputeDispatch& dispatch, const std::string& shader_dir,
                     const std::string& data_root);

    // Load config from JSON file
    ExperimentConfig load_config(const std::string& config_path);

    // Run experiment based on config
    ExperimentResult run(const ExperimentConfig& config);

    // Print results in machine-parseable format
    static void print_results(const ExperimentResult& result);

private:
    GpuDevice& device_;
    ShaderCompiler& compiler_;
    ComputeDispatch& dispatch_;
    TextureLoader loader_;
    CompressionPipeline pipeline_;
    Decompressor decompressor_;
    EvalMetrics metrics_;
    std::string data_root_;
};

} // namespace gtc
