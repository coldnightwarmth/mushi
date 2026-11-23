#pragma once
#include "CompiledState.hpp"
#include <array>
#include <optional>

namespace futari::recovered {
// Original frame directory consumed by 0c063740. Ten-byte big-endian records
// describe upright rectangles on the game's rotated 256x256 resource pages.
// The final word is the record ID; it is not an animation duration or a link.
struct SpriteFrame {
    uint16_t resource=0, width=0, height=0, id=0;
    uint8_t x=0, y=0;
    static constexpr uint32_t table=0x0c20bf14, countAddress=0x0c285028;

    static std::optional<SpriteFrame> read(Bus &bus,uint32_t index) {
        if(index>=bus.read(countAddress,4))return std::nullopt;
        auto address=table+index*10;
        SpriteFrame frame;
        frame.resource=bus.read(address,2);
        frame.x=bus.read(address+2,1);frame.y=bus.read(address+3,1);
        frame.width=bus.read(address+4,2);frame.height=bus.read(address+6,2);
        frame.id=bus.read(address+8,2);
        return frame;
    }
    // Seven words passed to draw submission 0c05df30 by wrapper 0c063740.
    // Positions are 16.16 fixed point. Their high words are passed unextended,
    // just as SHLR16 does; the downstream draw service applies signed clipping.
    std::array<uint32_t,7> drawArguments(uint32_t fixedX,uint32_t fixedY,uint32_t priority) const {
        return {fixedY>>16,fixedX>>16,priority,256u-y-height,x,height,width};
    }
};
}
