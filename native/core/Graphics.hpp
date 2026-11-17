#pragma once
#include "CompiledState.hpp"
#include <vector>

namespace futari {
// Native command-list renderer. Pixel math follows the documented CV1000 format
// and MAME's BSD-licensed CV1K reference (see THIRD_PARTY_NOTICES.md).
struct Graphics {
    std::vector<uint32_t> pixels=std::vector<uint32_t>(8192*4096);
    uint32_t list=0,scrollX=0,scrollY=0,clipX=0,clipY=0;
    uint64_t lists=0,draws=0,uploads=0;
    void execute(Bus &bus);
    void rgba(uint8_t *output) const;
};
}
