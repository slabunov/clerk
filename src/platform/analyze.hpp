#pragma once

#include "core/domain.hpp"

#include <filesystem>
#include <flat_map>
#include <string>
#include <utility>
#include <vector>

namespace clerk {
    struct Skipped {
        std::filesystem::path path;
        std::string           reason;
    };

    struct Scan {
        std::vector<Media>                                            media;
        std::vector<Skipped>                                          skipped;
        // full-resolution check of same-size close pairs
        std::flat_map<std::pair<std::uint32_t, std::uint32_t>, float> psnr;
    };

    Scan analyze(const std::filesystem::path &folder);
} // namespace clerk
