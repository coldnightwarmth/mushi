#pragma once
#include "RecoveredParticleInit.hpp"
#include <array>

namespace futari::recovered {
// Reviewed semantics of the 64-slot particle pool. These operations retain the
// original partial initialization: fields omitted below are intentionally left
// untouched. They are not yet substitutes for the original register ABI.
struct ParticlePool {
    static constexpr uint32_t base=0x0c51c8e8, stride=0x34, capacity=64;
    static constexpr uint32_t count=0x0c51d5e8, context=0x0c51d5ec;
    static constexpr uint32_t freeSlots=0x0c51d5f0, recycleHead=0x0c51d6f0, allocateTail=0x0c51d6f4;
    static constexpr uint32_t admissionFlag=0x0c38a654, admissionCounter=0x0c1e1050;

    // 0c099c30: only each active byte is cleared, not the entire object pool.
    static void reset(Bus &memory,uint32_t worldContext) {
        memory.write(context,worldContext,4);
        for(unsigned i=0;i<capacity;i++)memory.write(base+i*stride,0,1);
        memory.write(count,0,4);
        for(unsigned i=0;i<capacity;i++)memory.write(freeSlots+i*4,base+i*stride,4);
        memory.write(recycleHead,0,4);memory.write(allocateTail,0,4);
    }

    // 0c099c90. Ring indices are valid pool state (0..63). The admission fields'
    // gameplay meanings are not named beyond their observed allocation rule.
    static uint32_t spawn(Bus &memory,uint8_t type,uint32_t x,uint32_t y,
                          uint16_t priority,uint16_t angle,uint16_t spread) {
        if(memory.read(count,4)>=capacity)return 0;
        if(!memory.read(admissionFlag,2)&&int32_t(memory.read(admissionCounter,4))>14)return 0;
        auto tail=memory.read(allocateTail,4);
        auto object=memory.read(freeSlots+tail*4,4);
        memory.write(allocateTail,(tail+1)%capacity,4);
        memory.write(object,1,1);memory.write(object+1,0,1);memory.write(object+2,type,1);
        memory.write(object+0x0c,x,4);memory.write(object+0x10,y,4);
        memory.write(object+0x1c,priority,2);
        memory.write(object+0x14,0,4);memory.write(object+0x18,0,4);
        memory.write(object+0x1e,0,2);memory.write(object+0x20,angle,2);
        memory.write(object+0x24,0,2);memory.write(object+3,0,1);memory.write(object+4,0,1);
        memory.write(object+0x26,spread,2);memory.write(object+0x2b,255,1);
        memory.write(count,memory.read(count,4)+1,4);
        return object;
    }

    // 0c099d80 / 0c099da0: setters accept null and report whether they wrote.
    static bool setAnchor(Bus &memory,uint32_t object,uint8_t anchor) {
        if(!object)return false;
        memory.write(object+0x2b,anchor,1);return true;
    }
    static bool setVelocity(Bus &memory,uint32_t object,uint32_t speed,uint32_t angle) {
        if(!object)return false;
        PolarVelocity::write(memory,speed,angle,object+0x14,object+0x18);
        memory.write(object+0x1e,speed,2);memory.write(object+0x20,angle,2);
        memory.write(object,memory.read(object,1)|4,1);return true;
    }

    struct WorldStep {
        uint32_t scrollX;
        std::array<std::array<uint32_t,2>,4> anchorDeltas;
    };
    // Reviewed getters 0c0683c0, 0c068480 and 0c0680d0, as consumed by the
    // scheduler prologue. The scene producer of these fields is still AOT code.
    static WorldStep worldStep(Bus &memory,uint32_t worldContext) {
        WorldStep result;
        std::array<uint32_t,4> scroll;
        for(unsigned i=0;i<4;i++) {
            scroll[i]=memory.read(worldContext+0xbc+i*4,4);
            result.anchorDeltas[i]={memory.read(worldContext+0xfc+i*8,4),
                                   memory.read(worldContext+0x100+i*8,4)};
        }
        result.scrollX=scroll[memory.read(worldContext+0x54,4)?1:2];
        return result;
    }
    static void recycle(Bus &memory,uint32_t object) {
        auto head=memory.read(recycleHead,4);
        memory.write(freeSlots+head*4,object,4);
        memory.write(recycleHead,(head+1)%capacity,4);
        memory.write(object,0,1);memory.write(count,memory.read(count,4)-1,4);
    }

    // Body 0c099ad0..0c099bf2 of scheduler 0c099a70. Its world-query prologue is
    // supplied as a snapshot. Valid objects use anchor -1 (or another negative
    // byte) or 0..3. Scan termination uses the active count at entry, even when
    // callbacks spawn more objects. An initializer's return value is ignored;
    // a newly initialized object also moves and updates during this same pass.
    template<class Initialize,class Update>
    static void tick(Bus &memory,const WorldStep &world,Initialize initialize,Update update) {
        auto remaining=memory.read(count,4);
        for(uint32_t object=base;remaining;object+=stride) {
            if(!memory.read(object,1))continue;
            if(!memory.read(object+1,1)) {
                initialize(object,memory.read(object+2,1));
                memory.write(object+1,1,1);
            }
            --remaining;
            auto anchor=int8_t(memory.read(object+0x2b,1));
            if(anchor>=0) {
                const auto &delta=world.anchorDeltas.at(anchor);
                memory.write(object+0x0c,memory.read(object+0x0c,4)-delta[0],4);
                memory.write(object+0x10,memory.read(object+0x10,4)-delta[1],4);
            }
            auto x=memory.read(object+0x0c,4)+memory.read(object+0x14,4)+world.scrollX;
            auto y=memory.read(object+0x10,4)+memory.read(object+0x18,4);
            memory.write(object+0x10,y,4);memory.write(object+0x0c,x,4);
            if(x>0x00f00000u||int32_t(y)<0||int32_t(y)>0x01400000||
               !update(object,memory.read(object+2,1)))recycle(memory,object);
        }
    }
    template<class Initialize,class Update>
    static void tickFromContext(Bus &memory,Initialize initialize,Update update) {
        if(!memory.read(count,4))return;
        tick(memory,worldStep(memory,memory.read(context,4)),initialize,update);
    }
};
}
