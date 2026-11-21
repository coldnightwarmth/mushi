#pragma once
#include "CompiledState.hpp"
#include <vector>

namespace futari {
struct Graphics;
// Optional read-only sink for extraction, native presentation and write history.
struct GraphicsObserver {
    virtual ~GraphicsObserver() = default;
    virtual void written(int x,int y,int width,int height) = 0;
    virtual void draw(const Graphics &,uint32_t address,uint16_t attributes,
                      int x,int y,int width,int height) = 0;
    virtual void beforeWrite(const Graphics &,int,int,int,int) {}
    virtual void blit(const Graphics &,uint32_t,uint16_t,uint16_t,int,int,int,int,int,int,int,int,int,int,uint32_t) {}
};
// Native command-list renderer. Pixel math follows the documented CV1000 format
// and MAME's BSD-licensed CV1K reference (see THIRD_PARTY_NOTICES.md).
struct Graphics {
    GraphicsObserver *observer=nullptr;
    std::vector<uint32_t> pixels=std::vector<uint32_t>(8192*4096);
    uint32_t list=0,scrollX=0,scrollY=0,clipX=0,clipY=0;
    uint64_t lists=0,draws=0,uploads=0;
    void execute(Bus &bus);
    void rgba(uint8_t *output) const;
};
}
