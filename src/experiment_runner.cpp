#include "experiment_runner.h"
#include <fstream>
#include <chrono>
#include <cstdio>
#include <algorithm>

// Minimal JSON parsing (no external dependency)
// We parse a very simple JSON format for configs

namespace gtc {

ExperimentRunner::ExperimentRunner(GpuDevice& device, ShaderCompiler& compiler,
                                   ComputeDispatch& dispatch, const std::string& shader_dir,
                                   const std::string& data_root)
    : device_(device), compiler_(compiler), dispatch_(dispatch),
      loader_(device.device()), pipeline_(device, compiler, dispatch, shader_dir),
      data_root_(data_root) {}

ExperimentConfig ExperimentRunner::load_config(const std::string& config_path) {
    ExperimentConfig config;

    // Simple JSON parser for our config format
    std::ifstream file(config_path);
    if (!file.is_open()) {
        printf("[ExperimentRunner] Cannot open config: %s\n", config_path.c_str());
        return config;
    }

    std::string content((std::istreambuf_iterator<char>(file)),
                         std::istreambuf_iterator<char>());

    // Parse name
    auto find_str = [&](const std::string& key) -> std::string {
        auto pos = content.find("\"" + key + "\"");
        if (pos == std::string::npos) return "";
        pos = content.find("\"", pos + key.size() + 2);
        if (pos == std::string::npos) return "";
        pos++;
        auto end = content.find("\"", pos);
        if (end == std::string::npos) return "";
        return content.substr(pos, end - pos);
    };

    auto find_int = [&](const std::string& key, int default_val) -> int {
        auto pos = content.find("\"" + key + "\"");
        if (pos == std::string::npos) return default_val;
        pos = content.find(":", pos);
        if (pos == std::string::npos) return default_val;
        pos++;
        while (pos < content.size() && (content[pos] == ' ' || content[pos] == '\t')) pos++;
        return std::atoi(content.c_str() + pos);
    };

    config.name = find_str("name");
    if (config.name.empty()) config.name = "unnamed";
    config.quality_level = find_int("quality_level", 1);
    config.warmup_runs = find_int("warmup_runs", 1);
    config.measurement_runs = find_int("measurement_runs", 3);

    // Parse formats array
    auto formats_pos = content.find("\"formats\"");
    if (formats_pos != std::string::npos) {
        auto arr_start = content.find("[", formats_pos);
        auto arr_end = content.find("]", arr_start);
        if (arr_start != std::string::npos && arr_end != std::string::npos) {
            std::string arr = content.substr(arr_start, arr_end - arr_start + 1);
            // Extract format names
            for (int i = 0; i < GTC_FORMAT_COUNT; i++) {
                const auto& info = get_format_info((GtcFormat)i);
                if (arr.find(info.name) != std::string::npos) {
                    config.formats.push_back((GtcFormat)i);
                }
            }
        }
    }

    // Parse textures array
    auto tex_pos = content.find("\"textures\"");
    if (tex_pos != std::string::npos) {
        auto arr_start = content.find("[", tex_pos);
        auto arr_end = content.find("]", arr_start);
        if (arr_start != std::string::npos && arr_end != std::string::npos) {
            std::string arr = content.substr(arr_start + 1, arr_end - arr_start - 1);
            // Extract paths between quotes
            size_t pos = 0;
            while ((pos = arr.find("\"", pos)) != std::string::npos) {
                pos++;
                auto end = arr.find("\"", pos);
                if (end == std::string::npos) break;
                config.texture_paths.push_back(arr.substr(pos, end - pos));
                pos = end + 1;
            }
        }
    }

    // Default: if no formats specified, test BC1
    if (config.formats.empty()) {
        config.formats.push_back(GTC_FORMAT_BC1);
    }

    printf("[ExperimentRunner] Config '%s': %zu formats, %zu textures, quality=%d\n",
           config.name.c_str(), config.formats.size(), config.texture_paths.size(),
           config.quality_level);

    return config;
}

ExperimentResult ExperimentRunner::run(const ExperimentConfig& config) {
    ExperimentResult result;
    result.experiment_name = config.name;

    auto t0 = std::chrono::high_resolution_clock::now();

    // Prepare all format pipelines
    for (auto format : config.formats) {
        if (!pipeline_.prepare_format(format)) {
            result.error_message = "Failed to compile shader for " +
                                   std::string(get_format_info(format).name);
            return result;
        }
    }

    // Load textures
    std::vector<TextureData> textures;
    std::vector<std::string> tex_names;

    if (!config.texture_paths.empty()) {
        for (auto& path : config.texture_paths) {
            std::string full_path = path;
            // If relative, prepend data root
            if (path.find(':') == std::string::npos && path[0] != '/' && path[0] != '\\') {
                full_path = data_root_ + "/" + path;
            }
            auto tex = loader_.load_from_file(full_path);
            if (tex.width > 0) {
                textures.push_back(std::move(tex));
                // Extract filename for display
                size_t last_sep = path.find_last_of("/\\");
                tex_names.push_back(last_sep != std::string::npos ? path.substr(last_sep + 1) : path);
            } else {
                printf("[ExperimentRunner] WARNING: Failed to load: %s\n", full_path.c_str());
            }
        }
    }

    if (textures.empty()) {
        result.error_message = "No valid textures loaded";
        return result;
    }

    printf("[ExperimentRunner] Loaded %zu textures\n", textures.size());

    // Run compression + evaluation for each format and texture
    for (auto format : config.formats) {
        const auto& info = get_format_info(format);
        ExperimentResult::FormatAggregate agg;
        agg.format = format;

        for (size_t ti = 0; ti < textures.size(); ti++) {
            auto& tex_data = textures[ti];

            // Upload to GPU
            GpuTexture gpu_tex = loader_.upload_to_gpu(tex_data);
            if (!gpu_tex.texture) {
                printf("[ExperimentRunner] WARNING: Failed to upload texture %s\n", tex_names[ti].c_str());
                continue;
            }

            // Warmup runs
            for (int w = 0; w < config.warmup_runs; w++) {
                auto warmup_result = pipeline_.compress(gpu_tex, format, config.quality_level);
            }

            // Measurement runs
            double total_time = 0.0;
            CompressionResult compress_result;
            for (int m = 0; m < config.measurement_runs; m++) {
                compress_result = pipeline_.compress(gpu_tex, format, config.quality_level);
                if (compress_result.success) {
                    total_time += compress_result.compression_time_ms;
                }
            }

            loader_.release(gpu_tex);

            if (!compress_result.success) {
                printf("[ExperimentRunner] Compression failed for %s on %s: %s\n",
                       info.name, tex_names[ti].c_str(), compress_result.error_message.c_str());
                continue;
            }

            double avg_time = total_time / config.measurement_runs;

            // Decompress and evaluate
            TextureData decompressed = decompressor_.decompress(
                compress_result.compressed_data.data(),
                compress_result.width, compress_result.height, format);

            MetricsResult metrics = metrics_.evaluate(tex_data, decompressed);

            agg.avg_psnr += metrics.psnr_db;
            agg.avg_ssim += metrics.ssim;
            agg.avg_flip += metrics.flip;
            agg.avg_lpips += metrics.lpips_approx;
            agg.avg_time_ms += avg_time;
            agg.num_textures++;
        }

        // Average the metrics
        if (agg.num_textures > 0) {
            agg.avg_psnr /= agg.num_textures;
            agg.avg_ssim /= agg.num_textures;
            agg.avg_flip /= agg.num_textures;
            agg.avg_lpips /= agg.num_textures;
            agg.avg_time_ms /= agg.num_textures;
        }

        result.format_aggregates.push_back(agg);
    }

    auto t1 = std::chrono::high_resolution_clock::now();
    result.total_time_seconds = std::chrono::duration<double>(t1 - t0).count();
    result.success = true;

    return result;
}

void ExperimentRunner::print_results(const ExperimentResult& result) {
    printf("\n");
    printf("=== Experiment: %s ===\n", result.experiment_name.c_str());
    printf("total_time_seconds: %.1f\n", result.total_time_seconds);
    printf("status: %s\n", result.success ? "ok" : "FAILED");

    if (!result.success) {
        printf("error: %s\n", result.error_message.c_str());
        return;
    }

    for (auto& agg : result.format_aggregates) {
        const auto& info = get_format_info(agg.format);
        printf("\n---\n");
        printf("format:          %s\n", info.name);
        printf("avg_psnr:        %.4f\n", agg.avg_psnr);
        printf("avg_ssim:        %.4f\n", agg.avg_ssim);
        printf("avg_flip:        %.4f\n", agg.avg_flip);
        printf("avg_lpips:       %.4f\n", agg.avg_lpips);
        printf("avg_time_ms:     %.2f\n", agg.avg_time_ms);
        printf("num_textures:    %d\n", agg.num_textures);
        printf("---\n");
    }
}

} // namespace gtc
