#pragma once

#include "core/domain.hpp"

#include <expected>
#include <filesystem>
#include <string>

namespace clerk {
    std::expected<FileStamp, std::string> stampOf(const std::filesystem::path &path);

    std::expected<std::filesystem::path, std::string> moveToTrash(const std::filesystem::path &path,
                                                                  const FileStamp &            scanned);

    std::expected<void, std::string> putBack(const std::filesystem::path &trashed,
                                             const std::filesystem::path &original);

    // macOS Setting
    bool reduceMotion();
} // namespace clerk
