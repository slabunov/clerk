#pragma once

#include "core/domain.hpp"
#include "core/match.hpp"

#include <cstddef>
#include <cstdint>
#include <expected>
#include <filesystem>
#include <functional>
#include <span>
#include <stop_token>
#include <string>
#include <vector>

namespace clerk {
    struct Skipped {
        std::filesystem::path path;
        std::string           reason;
    };

    struct Scan {
        std::vector<Media>   media;
        std::vector<Skipped> skipped;
        PsnrTable            psnr; // full resolution check of same size pairs
    };

    std::vector<std::filesystem::path> list(const std::filesystem::path &folder);

    Scan analyze(std::span<const std::filesystem::path> files, const std::stop_token& stop = {},
                 const std::function<void(std::size_t, bool)>& onFile = {});

    struct Picture {
        std::size_t               width, height;
        std::vector<std::uint8_t> rgba;
    };

    std::expected<Picture, std::string> thumbnail(const std::filesystem::path &path, std::size_t side);
} // namespace clerk
