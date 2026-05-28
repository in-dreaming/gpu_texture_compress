#pragma once

#include "../sdk/include/gtc_formats.h"
#include <string>
#include <vector>

namespace gtc {

// Forward declaration to avoid circular include with experiment_runner.h
struct ExperimentResult;

class ResultsLogger {
public:
    explicit ResultsLogger(const std::string& tsv_path);

    // Create header if file doesn't exist
    void ensure_header();

    // Log one experiment result (one line per format)
    void log(const ExperimentResult& result,
             const std::string& git_commit,
             const std::string& status,
             const std::string& description);

    // Read all previous results
    struct HistoryEntry {
        std::string commit;
        std::string format;
        double avg_psnr = 0;
        double avg_ssim = 0;
        double avg_flip = 0;
        double time_ms = 0;
        std::string status;
        std::string description;
    };
    std::vector<HistoryEntry> read_history();

private:
    std::string tsv_path_;
};

} // namespace gtc
