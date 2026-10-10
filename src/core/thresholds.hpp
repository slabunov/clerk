#pragma once

// This file contains thresholds for the various criteria used to assess similarity between media items.
// Everything here is human-tuned and validated on a very small set of labeled pairs.
namespace clerk::thresholds {
    struct Term {
        float tau, scale, weight;
    };

    inline constexpr float kExactCandidatePrint = 0.3f;
    inline constexpr Term  kExactPsnr{.tau = 40.f, .scale = -4.f, .weight = 4.f};

    namespace similar {
        // 2-fold CV on labels: precision 0.77, recall 0.88 per pair
        inline constexpr Term  print{.tau = 0.465f, .scale = 0.04f, .weight = 4.f};
        inline constexpr float bias = 0.f;
    } // namespace similar

    namespace related {
        // 2-fold CV on labels: precision 0.83, recall 0.75 per pair
        inline constexpr Term  print{.tau = 0.709f, .scale = 0.073f, .weight = 2.26f};
        inline constexpr Term  backgroundColour{.tau = 0.544f, .scale = 0.164f, .weight = 1.49f};
        inline constexpr Term  person{.tau = 0.475f, .scale = 0.078f, .weight = 1.35f};
        inline constexpr float bias = -2.213f;
    } // namespace related

    // merge clusters while their average link probability is at least this
    inline constexpr float kGroupLink = 0.5f;
} // namespace clerk::thresholds
