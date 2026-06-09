#include "gpu_device.h"
#include "texture_loader.h"
#include "shader_compiler.h"
#include "compute_dispatch.h"
#include "compression_pipeline.h"
#include "decompressor.h"
#include "eval_metrics.h"
#include "experiment_runner.h"
#include "comparison_baker.h"
#include "results_logger.h"

#include <cstdio>
#include <cstring>
#include <string>

static void print_usage() {
    printf("Usage: gtc_runner [options]\n");
    printf("\n");
    printf("Options:\n");
    printf("  --info                  Print GPU device info and exit\n");
    printf("  --config <path>         Run experiment with given config JSON\n");
    printf("  --shader-dir <path>     Path to SDK shaders (default: ./shaders)\n");
    printf("  --data-dir <path>       Path to data directory (default: ./data)\n");
    printf("  --results <path>        Path to results.tsv (default: ./experiments/results.tsv)\n");
    printf("  --bake <path>           Bake comparison atlas (all test textures x all formats)\n");
    printf("  --thumb-size <n>        Thumbnail size for --bake (default: 256)\n");
    printf("  --quality-level <n>     Quality level for --bake (default: 1)\n");
    printf("  --help                  Print this help message\n");
}

int main(int argc, char* argv[]) {
    // Parse command line
    std::string config_path;
    std::string shader_dir = "shaders";
    std::string data_dir = "data";
    std::string results_path;  // Will be computed relative to config if not specified
    std::string bake_output_path;
    int thumb_size = 256;
    int bake_quality_level = 1;
    bool info_only = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--info") == 0) {
            info_only = true;
        } else if (strcmp(argv[i], "--config") == 0 && i + 1 < argc) {
            config_path = argv[++i];
        } else if (strcmp(argv[i], "--shader-dir") == 0 && i + 1 < argc) {
            shader_dir = argv[++i];
        } else if (strcmp(argv[i], "--data-dir") == 0 && i + 1 < argc) {
            data_dir = argv[++i];
        } else if (strcmp(argv[i], "--results") == 0 && i + 1 < argc) {
            results_path = argv[++i];
        } else if (strcmp(argv[i], "--bake") == 0 && i + 1 < argc) {
            bake_output_path = argv[++i];
        } else if (strcmp(argv[i], "--thumb-size") == 0 && i + 1 < argc) {
            thumb_size = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--quality-level") == 0 && i + 1 < argc) {
            bake_quality_level = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            print_usage();
            return 0;
        } else {
            printf("Unknown option: %s\n", argv[i]);
            print_usage();
            return 1;
        }
    }

    // Initialize GPU device
    gtc::GpuDevice device;
    if (!device.init()) {
        printf("ERROR: Failed to initialize GPU device\n");
        return 1;
    }

    device.print_info();

    if (info_only) {
        return 0;
    }

    // Initialize components
    gtc::ShaderCompiler compiler(device.device());
    gtc::ComputeDispatch dispatch(device.device());

    if (!bake_output_path.empty()) {
        gtc::ComparisonBaker baker(device, compiler, dispatch, shader_dir, data_dir);
        gtc::BakeConfig bake_config;
        bake_config.output_path = bake_output_path;
        bake_config.thumb_size = thumb_size;
        bake_config.quality_level = bake_quality_level;

        printf("\n=== Baking Comparison Atlas ===\n\n");
        gtc::BakeResult bake_result = baker.bake(bake_config);
        if (!bake_result.success) {
            printf("ERROR: Bake failed: %s\n", bake_result.error_message.c_str());
            return 1;
        }
        return 0;
    }

    if (config_path.empty()) {
        printf("ERROR: No --config or --bake specified. Use --help for usage.\n");
        return 1;
    }

    // Run experiment
    fprintf(stderr, "[main] Loading config: %s\n", config_path.c_str());
    fflush(stderr);
    gtc::ExperimentRunner runner(device, compiler, dispatch, shader_dir, data_dir);
    gtc::ExperimentConfig config = runner.load_config(config_path);

    printf("\n=== Starting Experiment: %s ===\n\n", config.name.c_str());
    fflush(stdout);

    gtc::ExperimentResult result = runner.run(config);

    // Print results
    gtc::ExperimentRunner::print_results(result);
    fflush(stdout);

    // Log results - each experiment config gets its own results file
    // e.g., config "quick_bc1" → experiments/results/quick_bc1.tsv
    if (results_path.empty()) {
        std::string cfg_dir = config_path;
        size_t last_sep = cfg_dir.find_last_of("/\\");
        std::string cfg_parent;
        if (last_sep != std::string::npos) {
            cfg_parent = cfg_dir.substr(0, last_sep);
            size_t parent_sep = cfg_parent.find_last_of("/\\");
            if (parent_sep != std::string::npos) {
                cfg_parent = cfg_parent.substr(0, parent_sep);
            }
        }
        // Create results directory alongside configs
        std::string results_dir = cfg_parent.empty() ? "results" : cfg_parent + "/results";
        // Use config name as filename
        results_path = results_dir + "/" + config.name + ".tsv";
    }

    // Ensure results directory exists
    {
        std::string dir = results_path;
        size_t sep = dir.find_last_of("/\\");
        if (sep != std::string::npos) {
            std::string dir_path = dir.substr(0, sep);
            // Simple mkdir (works on Windows)
            std::string mkdir_cmd = "mkdir \"" + dir_path + "\" 2>nul";
            system(mkdir_cmd.c_str());
        }
    }

    gtc::ResultsLogger logger(results_path);
    if (result.success) {
        logger.log(result, "manual", "keep", config.name);
    } else {
        logger.log(result, "manual", "crash", result.error_message);
    }

    printf("[Results] Logged to: %s\n", results_path.c_str());
    fflush(stdout);

    return result.success ? 0 : 1;
}
