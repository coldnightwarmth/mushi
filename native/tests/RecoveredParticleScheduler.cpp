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
int main(int argc,char **argv) {try {
    if(argc!=2)return 2;Memory original,native;
    std::ifstream input(argv[1],std::ios::binary);require(bool(input),"Missing program");
    input.read((char*)original.bytes.data(),original.bytes.size());native.bytes=original.bytes;
    std::array<uint32_t,30> handlers;
    for(unsigned i=0;i<handlers.size();i++)handlers[i]=original.read(0xc28e588+i*4,4);
    unsigned fixtures=0,callbacks=0,culled=0,worldQueries=0;
    for(bool actualWorld:{false,true})for(unsigned fixture=0;fixture<=260;fixture++) {
        const bool spawnDuringCallback=fixture==260;
        Pool::WorldStep world;world.scrollX=spawnDuringCallback?0:fixture&1?0xffff8000u:0x10000u;
        for(unsigned i=0;i<4;i++)world.anchorDeltas[i]={i*0x8000u,0u-i*0x4000u};
        for(auto memory:{&original,&native}) {
            Pool::reset(*memory,0xc600000);
            for(unsigned i=0;i<4;i++) {
                memory->write(0xc6000bc+i*4,spawnDuringCallback?0:i==1?0xffff8000u:i==2?0x10000u:0,4);
                memory->write(0xc6000fc+i*8,world.anchorDeltas[i][0],4);
                memory->write(0xc600100+i*8,world.anchorDeltas[i][1],4);
            }
            memory->write(0xc600054,fixture&1?fixture&2?0xffffffffu:1u:0u,4);
            for(unsigned i=0;i<64*Pool::stride;i++)memory->write(Pool::base+i,0,1);
            const auto population=spawnDuringCallback?2:fixture%65;
            memory->write(Pool::count,population,4);memory->write(Pool::recycleHead,fixture%64,4);
            memory->write(Pool::admissionFlag,1,2);memory->write(Pool::allocateTail,4,4);
            for(unsigned i=0;i<population;i++) {
                const auto slot=spawnDuringCallback?(i?63u:3u):(i*17)%64;
                const auto object=Pool::base+slot*Pool::stride;
                memory->write(object,1u<<((fixture+i)%8),1);
                memory->write(object+1,(i+fixture)%3?1:0,1);memory->write(object+2,(i+fixture)%15,1);
                constexpr uint32_t positions[]={0,1,0x00f00000,0x00f00001,0x01400000,0x01400001,0xffffffff,0x80000000,0x00640000};
                constexpr uint32_t velocities[]={0,1,0xffffffff,0x10000,0xffff0000};
                constexpr uint8_t anchors[]={255,128,0,1,2,3};
                memory->write(object+0x0c,spawnDuringCallback?0x640000:positions[(fixture+i)%9],4);
                memory->write(object+0x10,spawnDuringCallback?0x780000:positions[(fixture+i*3)%9],4);
                memory->write(object+0x14,spawnDuringCallback?0:velocities[(fixture+i)%5],4);
                memory->write(object+0x18,spawnDuringCallback?0:velocities[(fixture+i*2)%5],4);
                memory->write(object+0x2b,spawnDuringCallback?255:anchors[(fixture+i)%6],1);
            }
            memory->writes.clear();
        }
        using Calls=std::vector<std::array<uint32_t,3>>;
        Calls originalCalls,nativeCalls;
        auto invoke=[&](Memory &memory,Calls &calls,unsigned kind,uint32_t object,uint32_t type) {
            calls.push_back({kind,object,type});
            const auto slot=(object-Pool::base)/Pool::stride;
            memory.write(object+0x30,(fixture<<16)|(kind<<8)|slot,4);
            if(spawnDuringCallback&&slot==3&&kind==1)
                require(Pool::spawn(memory,7,0x640000,0x780000,153,0,0)==Pool::base+4*Pool::stride,"Callback allocation failed");
            return spawnDuringCallback||((fixture+slot+kind)%4!=0);
        };
        futari::CompiledState state;state.bus=&original;state.pc=0xc099a70;state.pr=0xc7ff000;state.r[15]=0xc7fe000;
        unsigned steps=0,queries=0;
        while(state.pc!=0xc7ff000) {
            require(++steps<20000,"Scheduler failed to finish");
            if(actualWorld&&(state.pc==0xc0683c0||state.pc==0xc068480||state.pc==0xc0680d0)) {
                ++queries;futari::runCompiledOriginal(state,state.cycles+1);continue;
            }
            if(state.pc==0xc0683c0) {
                require(state.r[4]==0xc600000&&state.r[5]<4,"Scroll query arguments differ");
                // The original chooses scroll query 1 when selector != 0, else 2.
                state.r[0]=state.r[5]==1?0xffff8000u:state.r[5]==2?0x10000u:0;
                if(spawnDuringCallback)state.r[0]=0;
                state.pc=state.pr;++queries;
            } else if(state.pc==0xc068480) {
                require(state.r[4]==0xc600000&&state.r[6]<4,"Anchor query arguments differ");
                auto delta=world.anchorDeltas[state.r[6]];
                original.write(state.r[5],delta[0],4);original.write(state.r[5]+4,delta[1],4);
                state.r[0]=0;state.pc=state.pr;++queries;
            } else if(state.pc==0xc0680d0) {
                require(state.r[4]==0xc600000,"Selector query argument differs");
                state.r[0]=fixture&1;state.pc=state.pr;++queries;
            } else {
                auto found=std::find(handlers.begin(),handlers.end(),state.pc);
                if(found!=handlers.end()) {
                    const auto object=state.r[4],type=original.read(object+2,1);
                    const unsigned kind=unsigned(found-handlers.begin())%2;
                    require(state.pc==handlers[type*2+kind],"Callback lookup differs");
                    state.r[0]=invoke(original,originalCalls,kind,object,type);state.pc=state.pr;
                } else futari::runCompiledOriginal(state,state.cycles+1);
            }
        }
        auto initialize=[&](uint32_t object,uint32_t type){return invoke(native,nativeCalls,0,object,type);};
        auto update=[&](uint32_t object,uint32_t type){return invoke(native,nativeCalls,1,object,type);};
        if(actualWorld)Pool::tickFromContext(native,initialize,update);
        else Pool::tick(native,world,initialize,update);
        require(originalCalls==nativeCalls,"Scheduler callback order differs");
        require(original.writes==native.writes,"Scheduler write order/value differs");
        require(std::equal(original.bytes.begin()+0x51c8e8,original.bytes.begin()+0x51d708,
                           native.bytes.begin()+0x51c8e8),"Scheduler pool state differs");
        if(spawnDuringCallback) {
            require(original.read(Pool::base+63*Pool::stride+0x30,4)==0,"Original last slot unexpectedly updated");
            require(original.read(Pool::base+4*Pool::stride+1,1)==1,"Spawned slot did not update in same scan");
        }
        callbacks+=originalCalls.size();worldQueries+=queries;
        culled+=unsigned(std::count_if(original.writes.begin(),original.writes.end(),[](auto w){return w[0]==Pool::count&&w[2]==4;}));
        ++fixtures;
    }
    std::cout<<"PASS "<<fixtures<<" scheduler fixtures / "<<callbacks<<" callbacks / "<<worldQueries
             <<" world queries (half original, half stubbed): initialization, same-pass updates, anchor motion, exact bounds, recycling and callback spawning; exact pool state and ordered writes ("<<culled<<" count writes)\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
