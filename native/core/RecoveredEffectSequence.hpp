#pragma once
#include "CompiledState.hpp"

namespace futari::recovered {
// Active portion of callback 0c07bf60, scheduled by 0c07b8c0. This describes
// the primary eight-frame effect only; the callback also draws a static glow.
// The four reachable variants come from the eight shot-configuration lists at
// 0c2860b8 (counts at 0c28686c): their type fields contain only 0,1,2,3.
struct EffectSequence8 {
    static constexpr uint32_t bases=0x0c285e90;
    uint8_t frame=0, countdown=0, delay=0;
    uint32_t primary(Bus &bus,unsigned variant) const {
        return bus.read(bases+variant*2,2)+int8_t(frame);
    }
    static uint32_t glow(unsigned variant){return 403+variant*3;}
    bool advance() {
        --countdown;
        if(int8_t(countdown)>=0)return true;
        countdown=delay;++frame;
        return int8_t(frame)<=7;
    }
};
}
