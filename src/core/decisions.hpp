#pragma once

#include "core/domain.hpp"
#include "core/thresholds.hpp"

#include <flat_set>

namespace clerk {
    struct Decisions {
        std::flat_set<std::uint32_t> trash;

        void toggle(const MediaId id) {
            if (!trash.erase(id.value)) {
                trash.insert(id.value);
            }
        }

        void keepBestQuality(const Group &g) {
            CLERK_ASSERT(g.level != Level::Related);
            trash.erase(g.reference.value);
            for (const Match &edge: g.edges) {
                if (edge.confidence.value >= thresholds::kAutoTrash) {
                    trash.insert(edge.a.value);
                }
            }
        }
    };
} // namespace clerk
