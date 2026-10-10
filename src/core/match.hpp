#pragma once

#include "core/domain.hpp"

#include <array>
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
        MediaId                              a, b;
        std::array<float, 3>                 atLeast;
        std::array<Kind, 3>                  kind;
        std::array<std::vector<Evidence>, 3> evidence;

        std::optional<Level> level() const;
        Match                at(Level level) const;
    };

    Assessment assess(const Media &a, const Media &b, const Metrics &m);

    struct Groups {
        std::vector<Group> exact, similar, related;
    };

    Groups group(std::span<const Media> media, std::span<const Assessment> pairs);
} // namespace clerk
