#pragma once

#include "core/check.hpp"

#include <array>
#include <cstdint>
#include <filesystem>
#include <string_view>
#include <utility>
#include <vector>

#include <sys/types.h>

namespace clerk {
    enum class Level : std::uint8_t {
        Exact,
        Similar,
        Related
    };

    enum class Kind : std::uint8_t {
        SameFile,
        SamePixels,
        Reencoded,
        Resized,
        Cropped,
        SameMoment,
        SameScene
    };

    enum class Criterion : std::uint8_t {
        FileBytes,
        Pixels,
        PixelDelta,
        FeaturePrint,
        BackgroundColour,
        Person
    };

    enum class MediaType : std::uint8_t {
        Image,
        Video
    };

    constexpr std::string_view name(Level v) {
        return std::array{"Exact", "Similar", "Related"}
                [std::to_underlying(v)];
    }

    constexpr std::string_view name(Kind v) {
        return std::array{"SameFile", "SamePixels", "Reencoded", "Resized", "Cropped", "SameMoment", "SameScene"}
                [std::to_underlying(v)];
    }

    constexpr std::string_view name(Criterion v) {
        return std::array{"FileBytes", "Pixels", "PixelDelta", "FeaturePrint", "BackgroundColour", "Person"}
                [std::to_underlying(v)];
    }

    struct MediaId {
        std::uint32_t value;

        friend auto operator<=>(MediaId, MediaId) = default;
    };

    struct Probability {
        explicit Probability(float v) : value{v} {
            CLERK_ASSERT(v >= 0.f && v <= 1.f);
        }

        Probability(double) = delete("use float in [0, 1]");

        float value;
    };

    struct Evidence {
        Criterion criterion;
        float     measured;
        float     contribution;
    };

    struct Match {
        MediaId               a, b;
        Level                 level;
        Kind                  kind;
        Probability           confidence;
        std::vector<Evidence> evidence;
    };

    struct FileStamp {
        dev_t          device;
        ino_t          inode;
        std::uintmax_t bytes;
        std::int64_t   mtimeNs;

        friend bool operator==(const FileStamp &, const FileStamp &) = default;
    };

    using Digest = std::array<std::uint8_t, 32>;
    inline constexpr std::size_t kPrintSize = 768;
    using Print = std::array<float, kPrintSize>;
    inline constexpr std::size_t kHistBins = 4 * 8 * 8;
    using Histogram = std::array<float, kHistBins>;
    inline constexpr std::size_t kMinSide = 64;

    struct Frame {
        Print     print;
        Histogram backgroundColour, personColour;
    };

    struct Quality {
        float megapixels, bitsPerPixel, sharpness, clipped, aesthetics;

        [[nodiscard]] float score() const;
    };

    struct Media {
        MediaId               id{};
        MediaType             type{};
        std::filesystem::path path;
        FileStamp             stamp{};
        std::uint32_t         width = 0, height = 0;
        double                seconds = 0;
        Digest                fileHash{}, pixelHash{};
        std::vector<Frame>    frames;
        Quality               quality{};

        Media() = default;

        Media(Media &&) = default;

        Media &operator=(Media &&) = default;

        Media(const Media &) = delete("refer to media by MediaId");
    };

    struct Group {
        Level                level;
        std::vector<MediaId> members;
        MediaId              reference;
        std::vector<Match>   edges;
    };
} // namespace clerk
