#pragma once
#include "CompiledState.hpp"

namespace futari::recovered {
// Positive-range contract of original 0c0631f0. Its upper bound is inclusive;
// asking for zero returns zero without consuming a random value. This helper
// is reviewed but not yet substituted for the original ABI/division sequence.
struct Random {
    static constexpr uint32_t seedAddress=0x0c1ed590;
    static uint16_t next(Bus &memory,uint16_t upperBound) {
        if(upperBound>32767)throw std::out_of_range("Original random bound must be nonnegative signed 16-bit");
        if(!upperBound)return 0;
        uint32_t seed=memory.read(seedAddress,4)*1103515245u+12345u;
        memory.write(seedAddress,seed,4);
        return (seed>>16)%(uint32_t(upperBound)+1);
    }
};
}
