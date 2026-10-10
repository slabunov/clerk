#pragma once

#include <source_location>
#include <string_view>

#include <spdlog/spdlog.h>

namespace clerk {
    [[noreturn]] inline void fail(std::string_view what, std::source_location at = std::source_location::current()) {
        spdlog::critical("Invariant failed: {}, {}:{}, {}", what, at.file_name(), at.line());
        spdlog::shutdown();
        std::abort();
    }
} // namespace clerk

// Apple Clang 21 has no __cpp_contracts, so we use this macro instead of C++ 26 contract_assert.
#define CLERK_ASSERT(cond) ((cond) ? void() : ::clerk::fail(#cond))
