#include "comparison_baker.h"
#include "bitmap_font5x7.h"
#include <chrono>
#include <cstdio>
#include <cmath>
#include <fstream>
#include <algorithm>
#include <cstring>
#include <set>

namespace gtc {

namespace {

double reinhard_tone(double v) {
    if (!std::isfinite(v) || v < 0.0) return 0.0;
    return v / (1.0 + v);
}

TextureData to_display_rgba8(const TextureData& src) {
    TextureData out;
    out.width = src.width;
    out.height = src.height;
    out.channels = 4;
    out.is_hdr = false;
    out.format = TexelFormat::RGBA8_UNORM;
    out.pixels.resize((size_t)src.width * src.height * 4);

    if (src.is_hdr) {
        const float* sf = reinterpret_cast<const float*>(src.pixels.data());
        for (size_t i = 0; i < (size_t)src.width * src.height; i++) {
            float r = (float)reinhard_tone(sf[i * src.channels + 0]);
            float g = (src.channels > 1) ? (float)reinhard_tone(sf[i * src.channels + 1]) : r;
            float b = (src.channels > 2) ? (float)reinhard_tone(sf[i * src.channels + 2]) : r;
            float a = (src.channels > 3) ? sf[i * src.channels + 3] : 1.0f;
            if (!std::isfinite(a)) a = 1.0f;
            a = std::clamp(a, 0.0f, 1.0f);
            out.pixels[i * 4 + 0] = (uint8_t)std::clamp(r * 255.0f, 0.0f, 255.0f);
            out.pixels[i * 4 + 1] = (uint8_t)std::clamp(g * 255.0f, 0.0f, 255.0f);
            out.pixels[i * 4 + 2] = (uint8_t)std::clamp(b * 255.0f, 0.0f, 255.0f);
            out.pixels[i * 4 + 3] = (uint8_t)std::clamp(a * 255.0f, 0.0f, 255.0f);
        }
    } else {
        memcpy(out.pixels.data(), src.pixels.data(),
               std::min(out.pixels.size(), src.pixels.size()));
    }
    return out;
}

void sample_bilinear(const uint8_t* src, int sw, int sh, float u, float v, uint8_t out[4]) {
    u = std::clamp(u, 0.0f, 1.0f);
    v = std::clamp(v, 0.0f, 1.0f);
    float fx = u * (sw - 1);
    float fy = v * (sh - 1);
    int x0 = (int)fx;
    int y0 = (int)fy;
    int x1 = std::min(x0 + 1, sw - 1);
    int y1 = std::min(y0 + 1, sh - 1);
    float tx = fx - x0;
    float ty = fy - y0;

    for (int c = 0; c < 4; c++) {
        float p00 = src[(y0 * sw + x0) * 4 + c];
        float p10 = src[(y0 * sw + x1) * 4 + c];
        float p01 = src[(y1 * sw + x0) * 4 + c];
        float p11 = src[(y1 * sw + x1) * 4 + c];
        float p0 = p00 + (p10 - p00) * tx;
        float p1 = p01 + (p11 - p01) * tx;
        out[c] = (uint8_t)std::clamp(p0 + (p1 - p0) * ty, 0.0f, 255.0f);
    }
}

std::vector<uint8_t> letterbox_thumbnail(const TextureData& src, int thumb_size) {
    TextureData ldr = to_display_rgba8(src);
    std::vector<uint8_t> canvas((size_t)thumb_size * thumb_size * 4, 0);

    if (ldr.width == 0 || ldr.height == 0) return canvas;

    float scale = std::min((float)thumb_size / ldr.width, (float)thumb_size / ldr.height);
    int dst_w = std::max(1, (int)std::round(ldr.width * scale));
    int dst_h = std::max(1, (int)std::round(ldr.height * scale));
    int off_x = (thumb_size - dst_w) / 2;
    int off_y = (thumb_size - dst_h) / 2;

    for (int y = 0; y < dst_h; y++) {
        float v = (dst_h > 1) ? (float)y / (dst_h - 1) : 0.0f;
        for (int x = 0; x < dst_w; x++) {
            float u = (dst_w > 1) ? (float)x / (dst_w - 1) : 0.0f;
            uint8_t px[4];
            sample_bilinear(ldr.pixels.data(), (int)ldr.width, (int)ldr.height, u, v, px);
            int dx = off_x + x;
            int dy = off_y + y;
            size_t idx = ((size_t)dy * thumb_size + dx) * 4;
            canvas[idx + 0] = px[0];
            canvas[idx + 1] = px[1];
            canvas[idx + 2] = px[2];
            canvas[idx + 3] = 255;
        }
    }
    return canvas;
}

void blit_thumbnail(std::vector<uint8_t>& atlas, int atlas_w, int atlas_h,
                    const std::vector<uint8_t>& thumb, int thumb_size,
                    int dst_x, int dst_y) {
    for (int y = 0; y < thumb_size; y++) {
        int ay = dst_y + y;
        if (ay < 0 || ay >= atlas_h) continue;
        for (int x = 0; x < thumb_size; x++) {
            int ax = dst_x + x;
            if (ax < 0 || ax >= atlas_w) continue;
            size_t src_idx = ((size_t)y * thumb_size + x) * 4;
            size_t dst_idx = ((size_t)ay * atlas_w + ax) * 4;
            atlas[dst_idx + 0] = thumb[src_idx + 0];
            atlas[dst_idx + 1] = thumb[src_idx + 1];
            atlas[dst_idx + 2] = thumb[src_idx + 2];
            atlas[dst_idx + 3] = thumb[src_idx + 3];
        }
    }
}

bool is_hdr_format(GtcFormat format) {
    return format == GTC_FORMAT_BC6H ||
           (format >= GTC_FORMAT_ASTC_4x4_HDR && format <= GTC_FORMAT_ASTC_12x12_HDR);
}

std::vector<GtcFormat> color_ldr_formats() {
    return {
        GTC_FORMAT_BC1, GTC_FORMAT_BC3, GTC_FORMAT_BC7,
        GTC_FORMAT_ASTC_4x4, GTC_FORMAT_ASTC_5x4, GTC_FORMAT_ASTC_5x5, GTC_FORMAT_ASTC_6x5,
        GTC_FORMAT_ASTC_6x6, GTC_FORMAT_ASTC_8x5, GTC_FORMAT_ASTC_8x6, GTC_FORMAT_ASTC_8x8,
        GTC_FORMAT_ASTC_10x5, GTC_FORMAT_ASTC_10x6, GTC_FORMAT_ASTC_10x8, GTC_FORMAT_ASTC_10x10,
        GTC_FORMAT_ASTC_12x10, GTC_FORMAT_ASTC_12x12
    };
}

std::vector<GtcFormat> all_hdr_formats() {
    return {
        GTC_FORMAT_BC6H,
        GTC_FORMAT_ASTC_4x4_HDR, GTC_FORMAT_ASTC_5x4_HDR, GTC_FORMAT_ASTC_5x5_HDR,
        GTC_FORMAT_ASTC_6x5_HDR, GTC_FORMAT_ASTC_6x6_HDR, GTC_FORMAT_ASTC_8x5_HDR,
        GTC_FORMAT_ASTC_8x6_HDR, GTC_FORMAT_ASTC_8x8_HDR, GTC_FORMAT_ASTC_10x5_HDR,
        GTC_FORMAT_ASTC_10x6_HDR, GTC_FORMAT_ASTC_10x8_HDR, GTC_FORMAT_ASTC_10x10_HDR,
        GTC_FORMAT_ASTC_12x10_HDR, GTC_FORMAT_ASTC_12x12_HDR
    };
}

} // namespace

ComparisonBaker::ComparisonBaker(GpuDevice& device, ShaderCompiler& compiler,
                                 ComputeDispatch& dispatch, const std::string& shader_dir,
                                 const std::string& data_root)
    : device_(device), compiler_(compiler), dispatch_(dispatch),
      loader_(device.device()), pipeline_(device, compiler, dispatch, shader_dir),
      data_root_(data_root) {}

std::vector<ComparisonBaker::BakeSection> ComparisonBaker::build_sections(const BakeConfig& config) {
    std::vector<BakeSection> sections;

    if (config.include_hdr_formats) {
        sections.push_back({"HDR Color", "hdr", all_hdr_formats()});
    }
    if (config.include_ldr_formats) {
        sections.push_back({"LDR Color", "color", color_ldr_formats()});
        sections.push_back({"Single Channel", "single_channel", {GTC_FORMAT_BC4}});
        sections.push_back({"Normal Map", "normal", {GTC_FORMAT_BC5}});
    }
    return sections;
}

bool ComparisonBaker::texture_matches_section(const TextureLoader::TestImage& img,
                                              const BakeSection& section) {
    if (section.category == "hdr") {
        return img.category == "hdr" || img.data.is_hdr;
    }
    if (img.data.is_hdr) return false;
    return img.category == section.category;
}

bool ComparisonBaker::write_layout_file(const std::string& path, int thumb_size,
                                        const std::vector<BakeSection>& sections,
                                        const std::vector<std::vector<std::string>>& section_tex_names,
                                        int atlas_width, int atlas_height) {
    std::ofstream out(path);
    if (!out.is_open()) return false;

    int section_label_h = 32;
    int header_h = std::max(48, thumb_size / 4);
    int section_gap = 8;

    out << "Comparison Atlas Layout\n";
    out << "========================\n";
    out << "thumb_size: " << thumb_size << "x" << thumb_size << "\n";
    out << "section_label_height: " << section_label_h << "\n";
    out << "header_height: " << header_h << "\n";
    out << "atlas_size: " << atlas_width << "x" << atlas_height << "\n";
    out << "layout: category sections, each with matching textures x formats only\n\n";

    int row_base = 0;
    for (size_t si = 0; si < sections.size(); si++) {
        if (section_tex_names[si].empty()) continue;

        out << "--- Section: " << sections[si].title << " ---\n";
        out << "category: " << sections[si].category << "\n";
        out << "atlas_row_start: " << row_base << " (includes section label + column headers)\n";
        out << "Column 0: Original\n";
        for (size_t fi = 0; fi < sections[si].formats.size(); fi++) {
            out << "Column " << (fi + 1) << ": "
                << get_format_info(sections[si].formats[fi]).name << "\n";
        }
        out << "Rows:\n";
        for (size_t ri = 0; ri < section_tex_names[si].size(); ri++) {
            out << "  Row " << ri << ": " << section_tex_names[si][ri] << "\n";
        }
        out << "\n";

        row_base += section_label_h + header_h + (int)section_tex_names[si].size() * thumb_size + section_gap;
    }
    return true;
}

BakeResult ComparisonBaker::bake(const BakeConfig& config) {
    BakeResult result;
    auto t0 = std::chrono::high_resolution_clock::now();

    std::string dataset_root = data_root_ + "/src_texture";
    auto test_images = loader_.load_test_dataset(dataset_root);
    if (test_images.empty()) {
        result.error_message = "No test images found in " + dataset_root;
        return result;
    }

    std::sort(test_images.begin(), test_images.end(),
              [](const TextureLoader::TestImage& a, const TextureLoader::TestImage& b) {
                  return a.name < b.name;
              });

    auto sections = build_sections(config);

    // Collect all formats to compile
    std::set<GtcFormat> all_formats;
    for (auto& sec : sections) {
        for (auto f : sec.formats) all_formats.insert(f);
    }
    for (auto format : all_formats) {
        if (!pipeline_.prepare_format(format)) {
            result.error_message = std::string("Failed to compile shader for ") +
                                   get_format_info(format).name;
            return result;
        }
    }

    int thumb = config.thumb_size;
    int section_label_h = 32;
    int header_h = std::max(48, thumb / 4);
    int section_gap = 8;

    // Group textures per section
    std::vector<std::vector<const TextureLoader::TestImage*>> section_images(sections.size());
    for (auto& img : test_images) {
        for (size_t si = 0; si < sections.size(); si++) {
            if (texture_matches_section(img, sections[si])) {
                section_images[si].push_back(&img);
            }
        }
    }

    // Compute atlas dimensions (width = max section width, height = sum of section heights)
    int atlas_w = 0;
    int atlas_h = 0;
    int active_sections = 0;
    for (size_t si = 0; si < sections.size(); si++) {
        if (section_images[si].empty()) continue;
        int sec_w = (1 + (int)sections[si].formats.size()) * thumb;
        atlas_w = std::max(atlas_w, sec_w);
        atlas_h += section_label_h + header_h + (int)section_images[si].size() * thumb;
        if (active_sections > 0) atlas_h += section_gap;
        active_sections++;
    }

    if (atlas_w == 0 || atlas_h == 0) {
        result.error_message = "No texture/format matches found in test dataset";
        return result;
    }

    std::vector<uint8_t> atlas((size_t)atlas_w * atlas_h * 4, 0);
    using namespace bitmap_font;

    std::vector<std::vector<std::string>> section_tex_names(sections.size());
    int processed = 0;
    int y_cursor = 0;
    bool first_section = true;

    for (size_t si = 0; si < sections.size(); si++) {
        auto& images = section_images[si];
        if (images.empty()) continue;

        if (!first_section) y_cursor += section_gap;
        first_section = false;

        auto& sec = sections[si];
        int sec_w = (1 + (int)sec.formats.size()) * thumb;

        // Section title bar
        fill_rect(atlas, atlas_w, atlas_h, 0, y_cursor, sec_w, section_label_h, 28, 48, 72);
        draw_string_in_cell(atlas, atlas_w, atlas_h, sec.title.c_str(),
                            0, y_cursor, sec_w, section_label_h, 255, 255, 255);
        y_cursor += section_label_h;

        // Column headers
        fill_rect(atlas, atlas_w, atlas_h, 0, y_cursor, sec_w, header_h, 40, 40, 40);
        draw_string_in_cell(atlas, atlas_w, atlas_h, "Original",
                            0, y_cursor, thumb, header_h, 220, 220, 220);
        for (size_t fi = 0; fi < sec.formats.size(); fi++) {
            const char* label = get_format_info(sec.formats[fi]).name;
            int col_x = (1 + (int)fi) * thumb;
            bool hdr = is_hdr_format(sec.formats[fi]);
            uint8_t cr = hdr ? 255 : 220;
            uint8_t cg = hdr ? 200 : 220;
            uint8_t cb = hdr ? 120 : 220;
            draw_string_in_cell(atlas, atlas_w, atlas_h, label, col_x, y_cursor, thumb, header_h, cr, cg, cb);
        }
        fill_rect(atlas, atlas_w, atlas_h, 0, y_cursor + header_h - 1, sec_w, 1, 80, 80, 80);
        y_cursor += header_h;

        printf("[Bake] Section '%s': %zu textures, %zu formats\n",
               sec.title.c_str(), images.size(), sec.formats.size());

        for (size_t row = 0; row < images.size(); row++) {
            auto& img = *images[row];
            section_tex_names[si].push_back(img.name);

            printf("[Bake]   (%zu/%zu) %s (%ux%u)\n",
                   row + 1, images.size(), img.name.c_str(),
                   img.data.width, img.data.height);

            auto orig_thumb = letterbox_thumbnail(img.data, thumb);
            blit_thumbnail(atlas, atlas_w, atlas_h, orig_thumb, thumb, 0, y_cursor);

            GpuTexture gpu_tex = loader_.upload_to_gpu(img.data);
            if (!gpu_tex.texture) {
                printf("[Bake] WARNING: Failed to upload %s\n", img.name.c_str());
                y_cursor += thumb;
                continue;
            }

            for (size_t fi = 0; fi < sec.formats.size(); fi++) {
                GtcFormat format = sec.formats[fi];
                auto compress_result = pipeline_.compress(gpu_tex, format, config.quality_level);
                if (!compress_result.success) {
                    printf("[Bake] WARNING: %s compress %s failed: %s\n",
                           img.name.c_str(), get_format_info(format).name,
                           compress_result.error_message.c_str());
                    continue;
                }

                TextureData decompressed = decompressor_.decompress(
                    compress_result.compressed_data.data(),
                    compress_result.width, compress_result.height, format);

                auto dec_thumb = letterbox_thumbnail(decompressed, thumb);
                int col = 1 + (int)fi;
                blit_thumbnail(atlas, atlas_w, atlas_h, dec_thumb, thumb, col * thumb, y_cursor);
            }

            loader_.release(gpu_tex);
            y_cursor += thumb;
            processed++;
        }
    }

    {
        std::string dir = config.output_path;
        size_t sep = dir.find_last_of("/\\");
        if (sep != std::string::npos) {
            std::string dir_path = dir.substr(0, sep);
            std::string mkdir_cmd = "mkdir \"" + dir_path + "\" 2>nul";
            system(mkdir_cmd.c_str());
        }
    }

    if (!TextureLoader::save_png(config.output_path, atlas, atlas_w, atlas_h)) {
        result.error_message = "Failed to write PNG: " + config.output_path;
        return result;
    }

    std::string layout_path = config.layout_path;
    if (layout_path.empty()) {
        layout_path = config.output_path + ".layout.txt";
    }
    write_layout_file(layout_path, thumb, sections, section_tex_names, atlas_w, atlas_h);

    auto t1 = std::chrono::high_resolution_clock::now();
    result.total_time_seconds = std::chrono::duration<double>(t1 - t0).count();
    result.success = true;
    result.num_textures = processed;
    result.num_formats = (int)all_formats.size();
    result.atlas_width = atlas_w;
    result.atlas_height = atlas_h;

    printf("\n[Bake] Atlas saved: %s (%dx%d)\n", config.output_path.c_str(), atlas_w, atlas_h);
    printf("[Bake] Layout: %s\n", layout_path.c_str());
    printf("[Bake] Textures: %d, Sections: %d, Time: %.1fs\n",
           result.num_textures, active_sections, result.total_time_seconds);

    return result;
}

} // namespace gtc
