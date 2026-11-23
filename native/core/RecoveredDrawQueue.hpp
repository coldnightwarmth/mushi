#pragma once
#include "CompiledState.hpp"

namespace futari::recovered {
// Reviewed original routine 0c05c394..0c05c3ea. This queue records a callback
// and payload in one of 512 stable FIFO priority buckets. It does not render.
struct DrawQueue {
    static constexpr uint32_t control=0x0c058338,buckets=0x0c058340;
    static constexpr uint32_t capacity=0x17700,nodeBytes=16;
    struct Result {uint32_t cursor,node,tail;bool full;};

    static Result append(Bus &memory,uint32_t callback,uint32_t payload,uint32_t priority) {
        const auto used=memory.read(control+4,4);
        // Equality is intentional: this is the original fixed-pool contract.
        if(used==capacity)return {used,0,0,true};
        const auto node=memory.read(control,4)+used;
        const auto bucket=buckets+(priority&511)*8;
        memory.write(control+4,used+nodeBytes,4);
        const auto tail=memory.read(bucket+4,4);
        memory.write(bucket+4,node,4);
        memory.write(node+8,payload,4);
        memory.write(node+4,callback,4);
        memory.write(tail ? tail:bucket,node,4);
        // New-node +0 is already zeroed by queue initialization/draining.
        // The original append deliberately leaves that word untouched.
        return {used+nodeBytes,node,tail,false};
    }

    // Exact ABI adapter for comparison and subsequent integration with the
    // compiled callers. Preserve even dead scratch registers and stack writes.
    static void call(CompiledState &c) {
        auto &r=c.r;
        r[15]-=4;c.wl(r[15],r[1]);
        r[15]-=4;c.wl(r[15],r[7]);
        const auto priority=r[6]&511;
        r[7]=buckets+priority*8;r[6]=control;
        const auto result=append(*c.bus,r[4],r[5],priority);
        r[0]=result.cursor;
        if(result.full)c.t(true);
        else {r[3]=result.node;c.t(result.tail==0);}
        r[7]=c.rl(r[15]);r[15]+=4;
        r[1]=c.rl(r[15]);r[15]+=4;
        c.pc=c.pr;c.cycles+=result.full ? 17:28;
    }
};
}
