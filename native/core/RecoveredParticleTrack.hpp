#pragma once
#include "CompiledState.hpp"
#include <optional>

namespace futari::recovered {
// Sequencing body of 0c099fe0, used by particle types 0 and 5. Unlike the
// projectile burst callback, this advances its timer BEFORE drawing. Fade can
// terminate a slow track before it reaches its final frame.
struct ParticleTrack {
    struct Draw {uint32_t frame;uint8_t fade;};
    static std::optional<Draw> advance(Bus &memory,uint32_t object) {
        auto fade=int16_t(uint16_t(memory.read(object+0x22,2)-4));
        memory.write(object+0x22,uint16_t(fade),2);
        if(fade<0){memory.write(object+0x22,0,2);return std::nullopt;}
        auto countdown=uint8_t(memory.read(object+4,1)-1);
        memory.write(object+4,countdown,1);
        if(int8_t(countdown)<0){
            auto delay=memory.read(object+5,1);
            auto frame=uint8_t(memory.read(object+3,1)+1);
            memory.write(object+4,delay,1);memory.write(object+3,frame,1);
            if(frame>11)return std::nullopt;
        }
        auto index=memory.read(object+3,1);
        return Draw{memory.read(memory.read(object+8,4)+index*2,2),uint8_t(fade)};
    }
};
}
