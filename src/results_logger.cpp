#include "results_logger.h"
#include "experiment_runner.h"
#include <fstream>
#include <sstream>
#include <cstdio>

namespace gtc {

ResultsLogger::ResultsLogger(const std::string& tsv_path)
    : tsv_path_(tsv_path) {}

void ResultsLogger::ensure_header() {
    // Check if file exists and has content
    std::ifstream check(tsv_path_);
    if (check.is_open()) {
        std::string first_line;
        if (std::getline(check, first_line) && !first_line.empty()) {
            return; // Header already exists
        }
    }

    std::ofstream file(tsv_path_);
    file << "commit\tformat\tavg_psnr\tavg_ssim\tavg_flip\ttime_ms\tstatus\tdescription\n";
}

void ResultsLogger::log(const ExperimentResult& result,
                        const std::string& git_commit,
                        const std::string& status,
                        const std::string& description) {
    ensure_header();

    std::ofstream file(tsv_path_, std::ios::app);
    if (!file.is_open()) {
        printf("[ResultsLogger] ERROR: Cannot open %s\n", tsv_path_.c_str());
        return;
    }

    for (auto& agg : result.format_aggregates) {
        const auto& info = get_format_info(agg.format);
        char line[512];
        snprintf(line, sizeof(line), "%s\t%s\t%.3f\t%.4f\t%.4f\t%.2f\t%s\t%s\n",
                 git_commit.c_str(), info.name,
                 agg.avg_psnr, agg.avg_ssim, agg.avg_flip,
                 agg.avg_time_ms, status.c_str(), description.c_str());
        file << line;
    }

    printf("[ResultsLogger] Logged to %s\n", tsv_path_.c_str());
}

std::vector<ResultsLogger::HistoryEntry> ResultsLogger::read_history() {
    std::vector<HistoryEntry> entries;

    std::ifstream file(tsv_path_);
    if (!file.is_open()) return entries;

    std::string line;
    std::getline(file, line); // Skip header

    while (std::getline(file, line)) {
        if (line.empty()) continue;

        HistoryEntry entry;
        std::istringstream iss(line);
        std::string token;

        if (std::getline(iss, entry.commit, '\t') &&
            std::getline(iss, entry.format, '\t') &&
            std::getline(iss, token, '\t')) { entry.avg_psnr = std::stod(token); }
        if (std::getline(iss, token, '\t')) entry.avg_ssim = std::stod(token);
        if (std::getline(iss, token, '\t')) entry.avg_flip = std::stod(token);
        if (std::getline(iss, token, '\t')) entry.time_ms = std::stod(token);
        std::getline(iss, entry.status, '\t');
        std::getline(iss, entry.description, '\t');

        entries.push_back(entry);
    }

    return entries;
}

} // namespace gtc
