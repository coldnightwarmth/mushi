#pragma once
#include <algorithm>
#include <cstdint>
#include <stdexcept>
#include <string>

// Register-shaped ABI for ahead-of-time compiled functions. There is deliberately
// no instruction fetch/decode loop here. The build-time translator emits C++.
namespace futari {
struct Bus {
    virtual ~Bus() = default;
    virtual uint32_t read(uint32_t address, unsigned size) = 0;
    virtual void write(uint32_t address, uint32_t value, unsigned size) = 0;
};
struct CompiledState {
    uint32_t r[16]{}, bank[8]{};
    uint32_t pc=0x0c000000, sr=0x700000f0, pr=0, gbr=0, vbr=0;
    uint32_t mach=0, macl=0, ssr=0, spc=0;
    uint64_t cycles=0, deadline=0;
    Bus *bus=nullptr;
    uint32_t rb(uint32_t a) { return bus->read(a,1); }
    uint32_t rw(uint32_t a) { return bus->read(a,2); }
    uint32_t rl(uint32_t a) { return bus->read(a,4); }
    void wb(uint32_t a,uint32_t v) { bus->write(a,v,1); }
    void ww(uint32_t a,uint32_t v) { bus->write(a,v,2); }
    void wl(uint32_t a,uint32_t v) { bus->write(a,v,4); }
    void t(bool v) { sr=(sr&~1u)|uint32_t(v); }
    void status(uint32_t v) {
        if ((sr^v)&0x20000000) for(int i=0;i<8;i++) std::swap(r[i],bank[i]);
        sr=v&0x700003f3;
    }
    [[noreturn]] void missing(uint32_t address) {
        pc=address;
        char message[100];
        snprintf(message,sizeof(message),"No native translation at %08x",address);
        throw std::runtime_error(message);
    }
    void div1(unsigned m,unsigned n) {
        const bool oldQ=sr&0x100, M=sr&0x200;
        bool Q=r[n]>>31;
        r[n]=(r[n]<<1)|(sr&1);
        uint32_t before=r[n];
        if (oldQ==M) { r[n]-=r[m]; Q=Q^(r[n]>before)^M; }
        else { r[n]+=r[m]; Q=Q^(r[n]<before)^M; }
        sr=(sr&~0x100u)|(uint32_t(Q)<<8);
        t(Q==M);
    }
    void mac(unsigned m,unsigned n,bool word) {
        int64_t a=word?int16_t(rw(r[m])):int32_t(rl(r[m])); r[m]+=word?2:4;
        int64_t b=word?int16_t(rw(r[n])):int32_t(rl(r[n])); r[n]+=word?2:4;
        uint64_t acc=(uint64_t(mach)<<32)|macl;
        if (sr&2) {
            int64_t sum=word?int64_t(int32_t(macl))+a*b:
                int64_t((acc&0xffffffffffffULL)^0x800000000000ULL)-0x800000000000LL+a*b;
            int64_t lo=word?INT32_MIN:-(1LL<<47), hi=word?INT32_MAX:((1LL<<47)-1);
            if(word) { if(sum<lo||sum>hi) mach|=1; macl=uint32_t(std::clamp(sum,lo,hi)); }
            else { acc=uint64_t(std::clamp(sum,lo,hi)); macl=acc;mach=(acc>>32)&0xffff; }
        } else { acc+=uint64_t(a*b);mach=acc>>32;macl=acc; }
    }
};
using NativePage = void (*)(CompiledState &);
void runCompiled(CompiledState &state, uint64_t deadline);
}
