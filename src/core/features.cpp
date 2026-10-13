#include "core/features.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>

namespace clerk {
    namespace {
        float luma(Rgba img, std::size_t y, std::size_t x) {
            return 0.299f * img[y, x, 0] + 0.587f * img[y, x, 1] + 0.114f * img[y, x, 2];
        }

        const std::array<float, 256> kLinear = [] {
            std::array<float, 256> t{};
            for (std::size_t i = 0; i < t.size(); ++i) {
                const float c = static_cast<float>(i) / 255.f;
                t[i] = c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
            }
            return t;
        }();

        void addLab(Histogram &h, std::uint8_t r8, std::uint8_t g8, std::uint8_t b8) {
            const float r = kLinear[r8], g = kLinear[g8], b = kLinear[b8];
            const auto  f = [](float t) {
                return t > 0.008856f ? std::cbrt(t) : 7.787f * t + 16.f / 116.f;
            };
            const float fx = f((0.4124f * r + 0.3576f * g + 0.1805f * b) / 0.95047f);
            const float fy = f(0.2126f * r + 0.7152f * g + 0.0722f * b);
            const float fz = f((0.0193f * r + 0.1192f * g + 0.9505f * b) / 1.08883f);
            const float L = 116.f * fy - 16.f, A = 500.f * (fx - fy), B = 200.f * (fy - fz);
            const auto  bin = [](float v, float lo, float width, int n) {
                return std::clamp(static_cast<int>((v - lo) / width), 0, n - 1);
            };
            h[std::size_t((bin(L, 0, 25, 4) * 8 + bin(A, -100, 25, 8)) * 8 + bin(B, -100, 25, 8))] += 1.f;
        }

        void normalise(Histogram &h) {
            if (const float sum = std::reduce(h.begin(), h.end()); sum > 0)
                for (auto &v: h)
                    v /= sum;
        }
    } // namespace

    Frame describe(Rgba rgba, Mask person, const Print &print) {
        CLERK_ASSERT(person.extent(0) == rgba.extent(0) && person.extent(1) == rgba.extent(1));
        Frame f{.print = print};

        for (std::size_t y = 0; y < rgba.extent(0); y += 2)
            for (std::size_t x = 0; x < rgba.extent(1); x += 2) {
                const bool isPerson = person[y, x] >= 128;
                addLab(isPerson ? f.personColour : f.backgroundColour, rgba[y, x, 0], rgba[y, x, 1], rgba[y, x, 2]);
            }
        normalise(f.personColour);
        normalise(f.backgroundColour);
        return f;
    }

    float sharpness(Rgba rgba) {
        double      sum = 0, sumSq = 0;
        std::size_t n = 0;
        for (std::size_t y = 1; y + 1 < rgba.extent(0); ++y)
            for (std::size_t x = 1; x + 1 < rgba.extent(1); ++x) {
                const double l = luma(rgba, y - 1, x) + luma(rgba, y + 1, x) + luma(rgba, y, x - 1) +
                                 luma(rgba, y, x + 1) - 4.0 * luma(rgba, y, x);
                sum += l;
                sumSq += l * l;
                ++n;
            }
        const double mean = sum / static_cast<double>(n);
        return static_cast<float>(sumSq / static_cast<double>(n) - mean * mean);
    }

    float clipped(Rgba rgba) {
        std::size_t hits = 0, n = 0;
        for (std::size_t y = 0; y < rgba.extent(0); y += 2)
            for (std::size_t x = 0; x < rgba.extent(1); x += 2, ++n) {
                const float l = luma(rgba, y, x);
                hits += l <= 2.f || l >= 253.f;
            }
        return static_cast<float>(hits) / static_cast<float>(n);
    }

    float psnr(Rgba a, Rgba b) {
        CLERK_ASSERT(a.extents() == b.extents());
        double se = 0;
        for (std::size_t y = 0; y < a.extent(0); ++y)
            for (std::size_t x = 0; x < a.extent(1); ++x)
                for (std::size_t c = 0; c < 3; ++c) {
                    const double d = static_cast<double>(a[y, x, c]) - static_cast<double>(b[y, x, c]);
                    se += d * d;
                }
        const double mse = se / static_cast<double>(a.extent(0) * a.extent(1) * 3);
        return mse == 0
                   ? std::numeric_limits<float>::infinity()
                   : static_cast<float>(10.0 * std::log10(255.0 * 255.0 / mse));
    }

    float distance(const Print &a, const Print &b) {
        return std::sqrt(std::transform_reduce(a.begin(), a.end(), b.begin(), 0.f, std::plus{},
                                               [](float x, float y) { return (x - y) * (x - y); }));
    }

    float hellinger(const Histogram &a, const Histogram &b) {
        if (std::reduce(a.begin(), a.end()) == 0.f || std::reduce(b.begin(), b.end()) == 0.f) {
            return std::numeric_limits<float>::quiet_NaN();
        }
        const float bc = std::transform_reduce(a.begin(), a.end(), b.begin(), 0.f, std::plus{},
                                               [](float x, float y) { return std::sqrt(x * y); });
        return std::sqrt(std::max(0.f, 1.f - bc));
    }

    float Quality::score() const {
        return std::log2(megapixels) + 0.5f * std::log2(bitsPerPixel) + 0.5f * std::log2(1.f + sharpness) -
               4.f * clipped + aesthetics;
    }
} // namespace clerk
