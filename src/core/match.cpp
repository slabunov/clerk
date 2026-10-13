#include "core/match.hpp"

#include "core/features.hpp"
#include "core/thresholds.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace clerk {
    namespace {
        constexpr float kNaN = std::numeric_limits<float>::quiet_NaN();

        float across(const Media &a, const Media &b, auto distance) {
            const auto closest = [&](const Frame &f, const Media &other) {
                float best = std::numeric_limits<float>::infinity();
                for (const Frame &g: other.frames)
                    if (const float d = distance(f, g); d < best) {
                        best = d;
                    }
                return std::isinf(best) ? kNaN : best;
            };

            if (a.frames.size() == 1) {
                return closest(a.frames[0], b);
            }
            if (b.frames.size() == 1) {
                return closest(b.frames[0], a);
            }

            const auto mean = [&](const Media &x, const Media &y) {
                float sum = 0;
                for (const Frame &f: x.frames) {
                    sum += closest(f, y);
                }
                return sum / static_cast<float>(x.frames.size());
            };
            return (mean(a, b) + mean(b, a)) / 2;
        }

        struct Score {
            float                 logOdds;
            std::vector<Evidence> evidence;

            void add(const Criterion c, const float x, const thresholds::Term t) {
                if (std::isnan(x)) {
                    return;
                }

                const float v = t.weight * std::tanh((t.tau - x) / t.scale);
                logOdds += v;
                evidence.push_back({.criterion = c, .measured = x, .contribution = v});
            }

            [[nodiscard]] float probability() const {
                return 1.f / (1.f + std::exp(-logOdds));
            }
        };

        Kind similarKind(const Media &a, const Media &b, const Metrics &m) {
            if (a.width == b.width && a.height == b.height && m.psnr >= 30.f) {
                return Kind::Reencoded;
            }
            if (a.type == MediaType::Video || b.type == MediaType::Video) {
                return Kind::SameMoment;
            }

            const float rb = static_cast<float>(b.width) / static_cast<float>(b.height);
            if (const float ra = static_cast<float>(a.width) / static_cast<float>(a.height);
                std::abs(ra - rb) / ra > 0.01f) {
                return Kind::Cropped;
            }
            return a.width != b.width ? Kind::Resized : Kind::SameMoment;
        }

        std::size_t pairIndex(const std::size_t i, const std::size_t j, const std::size_t n) {
            // i < j
            return i * n - i * (i + 1) / 2 + (j - i - 1);
        }

        using Cluster = std::vector<std::uint32_t>;
    } // namespace

    Metrics measure(const Media &a, const Media &b, const float psnr) {
        return {
            .sameFile = a.fileHash == b.fileHash,
            .samePixels = a.type == MediaType::Image && b.type == MediaType::Image && a.pixelHash == b.pixelHash,
            .psnr = psnr,
            .print = across(a, b, [](const Frame &f, const Frame &g) {
                return distance(f.print, g.print);
            }),
            .backgroundColour = across(a, b, [](const Frame &f, const Frame &g) {
                return hellinger(f.backgroundColour, g.backgroundColour);
            }),
            .person = across(a, b, [](const Frame &f, const Frame &g) {
                return hellinger(f.personColour, g.personColour);
            }),
        };
    }

    Assessment assess(const Media &a, const Media &b, const Metrics &m) {
        namespace t = thresholds;
        Score exact{.logOdds = -std::numeric_limits<float>::infinity(), .evidence = {}};
        auto  exactKind = Kind::Reencoded;

        if (m.sameFile || m.samePixels) {
            exactKind = m.sameFile ? Kind::SameFile : Kind::SamePixels;
            exact = {
                .logOdds = std::numeric_limits<float>::infinity(),
                .evidence = {
                    {
                        .criterion = m.sameFile ? Criterion::FileBytes : Criterion::Pixels, .measured = 1.f,
                        .contribution = 0.f
                    }
                }
            };
        } else if (!std::isnan(m.psnr)) {
            exact.logOdds = 0;
            exact.add(Criterion::PixelDelta, m.psnr, t::kExactPsnr);
        }

        Score similar{.logOdds = t::similar::bias, .evidence = {}};
        similar.add(Criterion::FeaturePrint, m.print, t::similar::print);

        Score related{.logOdds = t::related::bias, .evidence = {}};
        related.add(Criterion::FeaturePrint, m.print, t::related::print);
        related.add(Criterion::BackgroundColour, m.backgroundColour, t::related::backgroundColour);
        related.add(Criterion::Person, m.person, t::related::person);

        const float pe = exact.probability();
        const float ps = std::max(pe, similar.probability());
        const float pr = std::max(ps, related.probability());
        return {
            .a = a.id, .b = b.id, .atLeast = {pe, ps, pr}, .kind = {exactKind, similarKind(a, b, m), Kind::SameScene},
            .evidence = {std::move(exact.evidence), std::move(similar.evidence), std::move(related.evidence)}
        };
    }

    std::optional<Level> Assessment::level() const {
        for (Level l: {Level::Exact, Level::Similar, Level::Related})
            if (atLeast[std::to_underlying(l)] >= 0.5f) {
                return l;
            }
        return std::nullopt;
    }

    Match Assessment::at(const Level level) const {
        const auto i = std::to_underlying(level);
        return {
            .a = a, .b = b, .level = level, .kind = kind[i], .confidence = Probability{atLeast[i]},
            .evidence = evidence[i]
        };
    }

    std::vector<Assessment> assessAll(const std::span<const Media> media, const PsnrTable &psnr) {
        std::vector<Assessment> pairs;
        pairs.reserve(media.size() * (media.size() - 1) / 2);
        for (std::uint32_t i = 0; i < media.size(); ++i)
            for (std::uint32_t j = i + 1; j < media.size(); ++j) {
                const auto  it = psnr.find({i, j});
                const float db = it == psnr.end() ? std::numeric_limits<float>::quiet_NaN() : it->second;
                pairs.push_back(assess(media[i], media[j], measure(media[i], media[j], db)));
            }
        return pairs;
    }

    Groups group(std::span<const Media> media, std::span<const Assessment> pairs) {
        const std::size_t n = media.size();
        CLERK_ASSERT(pairs.size() == n * (n - 1) / 2);
        for (std::size_t i = 0; i < n; ++i)
            CLERK_ASSERT(media[i].id.value == i);

        const auto pair = [&](const std::uint32_t i, const std::uint32_t j) -> const Assessment & {
            return pairs[i < j ? pairIndex(i, j, n) : pairIndex(j, i, n)];
        };
        const auto p = [&](const Level level, const std::uint32_t i, const std::uint32_t j) {
            return pair(i, j).atLeast[std::to_underlying(level)];
        };

        const auto merge = [&](std::vector<Cluster> clusters, const Level level) {
            const bool single = level == Level::Exact;
            for (;;) {
                float       best = -1;
                std::size_t bi = 0, bj = 0;
                for (std::size_t i = 0; i < clusters.size(); ++i)
                    for (std::size_t j = i + 1; j < clusters.size(); ++j) {
                        float sum = 0, max = 0;

                        for (const auto x: clusters[i])
                            for (const auto y: clusters[j]) {
                                sum += p(level, x, y);
                                max = std::max(max, p(level, x, y));
                            }

                        const float s = single
                                            ? max
                                            : sum / static_cast<float>(clusters[i].size() * clusters[j].size());
                        if (s > best) {
                            best = s, bi = i, bj = j;
                        }
                    }

                if (best < thresholds::kGroupLink) {
                    return clusters;
                }
                clusters[bi].append_range(clusters[bj]);
                clusters.erase(clusters.begin() + static_cast<std::ptrdiff_t>(bj));
            }
        };

        const auto toGroups = [&](const std::vector<Cluster> &clusters, const Level level) {
            std::vector<Group> groups;
            for (const Cluster &c: clusters) {
                if (c.size() < 2) {
                    continue;
                }

                const bool samePixels = std::ranges::all_of(c, [&](auto i) {
                    return media[i].pixelHash == media[c[0]].pixelHash;
                });

                const auto better = [&](const std::uint32_t x, const std::uint32_t y) {
                    if (samePixels) return media[y].stamp.bytes < media[x].stamp.bytes;
                    return media[y].quality.score() > media[x].quality.score();
                };

                std::uint32_t ref = c[0];
                for (const auto i: c)
                    if (better(ref, i)) {
                        ref = i;
                    }

                Group g{.level = level, .members = {}, .reference = MediaId{ref}, .edges = {}};
                for (const auto i: c) {
                    g.members.push_back(MediaId{i});
                    if (i == ref) {
                        continue;
                    }

                    std::uint32_t to = ref;
                    for (const auto j: c)
                        if (j != i && p(level, i, to) < 0.5f && p(level, i, j) > p(level, i, to)) {
                            to = j;
                        }
                    Match edge = pair(i, to).at(level);
                    if (edge.a.value != i) {
                        std::swap(edge.a, edge.b);
                    }
                    g.edges.push_back(std::move(edge));
                }
                groups.push_back(std::move(g));
            }
            return groups;
        };

        std::vector<Cluster> clusters(n);
        for (std::uint32_t i = 0; i < n; ++i) {
            clusters[i] = {i};
        }
        Groups out;
        clusters = merge(std::move(clusters), Level::Exact);
        out.exact = toGroups(clusters, Level::Exact);
        clusters = merge(std::move(clusters), Level::Similar);
        out.similar = toGroups(clusters, Level::Similar);
        clusters = merge(std::move(clusters), Level::Related);
        out.related = toGroups(clusters, Level::Related);
        return out;
    }
} // namespace clerk
