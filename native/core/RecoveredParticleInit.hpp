#pragma once
#include "RecoveredRandom.hpp"

namespace futari::recovered {
// Original 0c063680: table-based components, with the original 32-bit product
// wrap and y-before-x store order. The caller supplies optional destinations.
struct PolarVelocity {
    static constexpr uint32_t tableAddress=0x0c1ed5c0;
    static void write(Bus &memory,uint32_t speed,uint32_t angle,uint32_t x,uint32_t y) {
        angle&=511;
        if(y)memory.write(y,memory.read(tableAddress+((angle+128)&511)*4,4)*speed,4);
        if(x)memory.write(x,memory.read(tableAddress+angle*4,4)*speed,4);
    }
};

// Original particle initializers 0c099e00 (type 0) and 0c099ef0 (type 5).
// Flag bit 2 preserves supplied velocity; otherwise a randomized polar velocity
// is generated. The spread contract here is nonnegative signed 16-bit, matching
// the reviewed random helper. No ABI/runtime replacement is made yet.
struct ParticleInit {
    static void initialize(Bus &memory,uint32_t object,bool slow) {
        const auto delay=slow?20u:3u;
        memory.write(object+4,delay,1);
        memory.write(object+5,delay,1);
        memory.write(object+0x22,255-Random::next(memory,16),2);
        if(!(memory.read(object,1)&4)) {
            auto speed=Random::next(memory,63)*2+8;
            auto angle=memory.read(object+0x20,2);
            auto spread=memory.read(object+0x26,2);
            angle+=Random::next(memory,spread)-spread/2;
            PolarVelocity::write(memory,speed,angle,object+0x14,object+0x18);
        }
        const auto table=Random::next(memory,2);
        memory.write(object+8,0x0c28e2b0,4);
        if(table==1)memory.write(object+8,0x0c28e2c8,4);
        if(table==2)memory.write(object+8,0x0c28e2e0,4);
        // A zero random flip leaves the existing word untouched.
        if(Random::next(memory,1))memory.write(object+0x24,1,2);
        memory.write(object+3,6,1);
    }
};
}
