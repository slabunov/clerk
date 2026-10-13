#pragma once

#include "core/domain.hpp"

#include <array>
#include <flat_map>
#include <optional>
#include <span>

namespace clerk {
    struct Metrics {
        bool  sameFile, samePixels;
        float psnr;
        float print, backgroundColour, person;
    };

    Metrics measure(const Media &a, const Media &b, float psnr);

    struct Assessment {
        MediaId                              a{}, b{};
        std::array<float, 3>                 atLeast{};
        std::array<Kind, 3>                  kind{};
        std::array<std::vector<Evidence>, 3> evidence;

        [[nodiscard]] std::optional<Level> level() const;

        [[nodiscard]] Match at(Level level) const;
    };

    Assessment assess(const Media &a, const Media &b, const Metrics &m);

    using PsnrTable = std::flat_map<std::pair<std::uint32_t, std::uint32_t>, float>;

    std::vector<Assessment> assessAll(std::span<const Media> media, const PsnrTable &psnr);

    struct Groups {
        std::vector<Group> exact, similar, related;
    };

    Groups group(std::span<const Media> media, std::span<const Assessment> pairs);
} // namespace clerk
