#pragma once

#include "core/domain.hpp"

#include <mdspan>

namespace clerk {
    using RgbaExtents = std::extents<std::size_t, std::dynamic_extent, std::dynamic_extent, 4>;
    using Rgba = std::mdspan<const std::uint8_t, RgbaExtents>;
    using Mask = std::mdspan<const std::uint8_t, std::dextents<std::size_t, 2> >;

    Frame describe(Rgba rgba, Mask person, const Print &print);

    float sharpness(Rgba rgba);
    float clipped(Rgba rgba);
    float psnr(Rgba a, Rgba b);

    float distance(const Print &a, const Print &b);

    float hellinger(const Histogram &a, const Histogram &b);
} // namespace clerk
