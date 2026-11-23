#pragma once
#include "RecoveredDrawQueue.hpp"

namespace futari::recovered {
// Reviewed queue body 0c05c3f4..0c05c442. Interrupt-mask entry/exit and graphics
// command submission belong to the caller, not this extraction-level service.
// This is not installed as a runtime replacement: callback/slice continuations
// still execute the compiled original until their ABI is recovered separately.
template<class Invoke> unsigned drainDrawQueue(Bus &memory,Invoke invoke) {
    unsigned calls=0;
    for(unsigned priority=0;priority<512;priority++){
        auto bucket=DrawQueue::buckets+priority*8;
        auto node=memory.read(bucket,4);
        memory.write(bucket,0,4);memory.write(bucket+4,0,4);
        // The original checks the decremented bucket count before executing
        // its head. Bucket 511 is cleared but never invoked or unlinked.
        if(priority==511)break;
        while(node){
            invoke(memory.read(node+4,4),memory.read(node+8,4));++calls;
            // A callback can modify links or append to a later bucket. Read
            // next only after it returns; clear buckets before invoking them.
            auto next=memory.read(node,4);memory.write(node,0,4);node=next;
        }
    }
    memory.write(DrawQueue::control+4,0,4);
    return calls;
}
}
