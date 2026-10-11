#include "platform/files.hpp"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <cerrno>
#include <cstring>

#include <sys/stat.h>

namespace clerk {
    std::expected<FileStamp, std::string> stampOf(const std::filesystem::path &path) {
        struct stat st{};
        if (::stat(path.c_str(), &st) != 0) {
            return std::unexpected(std::strerror(errno));
        }
        return FileStamp{
            st.st_dev, st.st_ino, static_cast<std::uintmax_t>(st.st_size),
            static_cast<std::int64_t>(st.st_mtimespec.tv_sec) * 1'000'000'000 + st.st_mtimespec.tv_nsec
        };
    }

    std::expected<std::filesystem::path, std::string> moveToTrash(const std::filesystem::path &path,
                                                                  const FileStamp &            scanned) {
        const auto now = stampOf(path);
        if (!now) {
            return std::unexpected(now.error());
        }
        if (*now != scanned) {
            return std::unexpected("the file changed after the scan");
        }
        NSURL *  trashed = nil;
        NSError *error = nil;
        if (![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:@(path.c_str())]

        resultingItemURL:
            &trashed
    error:
        &error])
        {
            return std::unexpected(std::string{error.localizedDescription.UTF8String});
        }
        return std::filesystem::path{trashed.path.UTF8String};
    }

    std::expected<void, std::string> putBack(const std::filesystem::path &trashed,
                                             const std::filesystem::path &original) {
        NSError *error = nil;
        if (![NSFileManager.defaultManager moveItemAtURL:[NSURL fileURLWithPath:@(trashed.c_str())]

        toURL:
            [NSURL fileURLWithPath:@(original.c_str())]

    error:
        &error])
        {
            return std::unexpected(std::string{error.localizedDescription.UTF8String});
        }
        return {};
    }

    bool reduceMotion() { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }
} // namespace clerk
