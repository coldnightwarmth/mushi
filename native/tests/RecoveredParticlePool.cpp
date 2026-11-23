#include "RecoveredParticlePool.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <vector>
namespace futari {void runCompiledOriginal(CompiledState &,uint64_t);}
using Pool=futari::recovered::ParticlePool;
struct Memory: futari::Bus {
    std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
    std::vector<std::array<uint32_t,3>> writes;
    uint32_t read(uint32_t a,unsigned n)override {
        uint32_t v=0;for(unsigned i=0;i<n;i++)v=v<<8|bytes.at((a&0x7fffff)+i);return v;
    }
    void write(uint32_t a,uint32_t v,unsigned n)override {
        if(a<0xc700000)writes.push_back({a,v&(n==4?0xffffffffu:n==2?65535u:255u),n});
        for(unsigned i=0;i<n;i++)bytes.at((a&0x7fffff)+i)=v>>((n-1-i)*8);
    }
};
static void require(bool condition,const char *message) {if(!condition)throw std::runtime_error(message);}
static futari::CompiledState stateFor(Memory &memory,uint32_t entry) {
    futari::CompiledState state;state.bus=&memory;state.pc=entry;state.pr=0xc7ff000;state.r[15]=0xc7fe000;return state;
}
static uint32_t run(futari::CompiledState state) {
    unsigned steps=0;while(state.pc!=0xc7ff000) {
        require(++steps<20000,"Pool routine failed to return");
        futari::runCompiledOriginal(state,state.cycles+1);
    }return state.r[0];
}
int main(int argc,char **argv) {try {
    if(argc!=2)return 2;Memory original,native;
    std::ifstream input(argv[1],std::ios::binary);require(bool(input),"Missing program");
    input.read((char*)original.bytes.data(),original.bytes.size());native.bytes=original.bytes;
    unsigned resets=0,spawns=0,setters=0;
    for(uint32_t pattern:{0u,0x55u,0xffu})for(uint32_t context:{0u,0xc600000u,0xffffffffu}) {
        for(auto memory:{&original,&native}) {
            for(unsigned i=0;i<0xe20;i++)memory->write(Pool::base+i,pattern+i,1);
            memory->writes.clear();
        }
        auto state=stateFor(original,0xc099c30);state.r[4]=context;run(state);Pool::reset(native,context);
        require(original.writes==native.writes,"Pool reset writes differ");
        require(std::equal(original.bytes.begin()+0x51c8e8,original.bytes.begin()+0x51d708,
                           native.bytes.begin()+0x51c8e8),"Pool reset bytes differ");++resets;
    }
    for(uint32_t count:{0u,1u,15u,63u,64u,65u,0xffffffffu})
    for(uint32_t flag:{0u,1u,65535u})for(uint32_t counter:{0u,14u,15u,0xffffffffu})
    for(uint32_t tail:{0u,1u,62u,63u})for(uint32_t type:{0u,5u,14u,255u}) {
        for(auto memory:{&original,&native}) {
            Pool::reset(*memory,0xc600000);
            for(unsigned i=0;i<Pool::capacity*Pool::stride;i++)memory->write(Pool::base+i,i*13+type,1);
            memory->write(Pool::count,count,4);memory->write(Pool::admissionFlag,flag,2);
            memory->write(Pool::admissionCounter,counter,4);memory->write(Pool::allocateTail,tail,4);
            memory->writes.clear();
        }
        auto state=stateFor(original,0xc099c90);state.r[4]=type;
        state.r[5]=0xffffffffu-type;state.r[6]=0x80000000u+tail;state.r[7]=0xff00u+type;
        original.write(state.r[15],0xfedcu,4);original.write(state.r[15]+4,0xab98u,4);
        auto result=run(state),expected=Pool::spawn(native,type,state.r[5],state.r[6],state.r[7],0xfedc,0xab98);
        require(result==expected,"Spawn return differs");
        require(original.writes==native.writes,"Spawn writes differ");++spawns;
    }
    for(uint32_t object:{0u,Pool::base})for(uint32_t value:{0u,1u,255u,256u,0x80000000u,0xffffffffu}) {
        original.writes.clear();native.writes.clear();
        auto state=stateFor(original,0xc099d80);state.r[4]=object;state.r[5]=value;
        require(run(state)==Pool::setAnchor(native,object,value),"Anchor return differs");
        require(original.writes==native.writes,"Anchor writes differ");++setters;
        for(uint32_t angle:{0u,127u,511u,512u,0xffffffffu}) {
            original.writes.clear();native.writes.clear();
            auto velocity=stateFor(original,0xc099da0);velocity.r[4]=object;velocity.r[5]=value;velocity.r[6]=angle;
            require(run(velocity)==Pool::setVelocity(native,object,value,angle),"Velocity return differs");
            require(original.writes==native.writes,"Velocity writes differ");++setters;
        }
    }
    std::cout<<"PASS "<<resets<<" pool resets / "<<spawns<<" allocation cases / "<<setters
             <<" setters: capacity/admission, ring wrap, partial initialization, null handling and exact ordered writes\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
