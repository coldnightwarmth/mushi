#pragma once
#include "Board.hpp"
#include <unordered_map>
#include <map>
namespace futari {
// Presentation records retain the native draw order and original source pixels.
// The board's VRAM and collision state are never edited by display options.
struct NativePresentation {
    struct Tag { int priority=-1;bool scenery=false;uint32_t callback=0,object=0; };
    struct Draw {int x,y,w,h,layer;uint16_t attr,alpha;uint32_t tint;std::vector<uint32_t> source;uint64_t family=0;int priority=-1;int group=3;};
    struct Variant {uint64_t hash;std::vector<uint32_t> pixels;};
    std::unordered_map<uint32_t,Tag> tags;
    std::vector<Draw> draws;
    std::shared_ptr<std::vector<Draw>> displayDraws;
    std::map<std::pair<int,int>,std::shared_ptr<std::vector<Draw>>> buffers;
    // 6..9: visible FX/player/enemy/other actor partitions. 10..13: their
    // observed random variants. Group membership follows native draw bands.
    std::array<std::vector<uint32_t>,14> planes;
    std::unordered_map<uint64_t,std::vector<Variant>> variants;
    size_t variantBytes=0;uint64_t tick=0;
    int originX=0,originY=0,displayOriginX=0,displayOriginY=0;
    bool ready=false,randomTrails=false;
    void tag(Board &,uint32_t,uint32_t,unsigned);
    // A busy native frame may repeat a display buffer. Select by the actual
    // display registers, rather than assuming a fixed one-frame delay.
    void begin(uint64_t frame){tick=frame;draws.clear();ready=false;}
    void clear(){draws.clear();displayDraws.reset();buffers.clear();variants.clear();variantBytes=0;ready=false;}
    void complete(int scrollX,int scrollY);
    void capture(const Graphics &,uint32_t,uint16_t,uint16_t,int,int,int,int,int,int,int,int,int,int,uint32_t);
    void finish();
    void rgba(int layer,int width,int height,uint8_t *out,int scrollX=-1,int scrollY=-1);
};
}
