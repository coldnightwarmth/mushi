#include "RecoveredParticleTrack.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <vector>

namespace futari {void runCompiledOriginal(CompiledState &,uint64_t);}
struct Memory: futari::Bus {
    std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
    std::vector<std::array<uint32_t,3>> writes;
    uint32_t read(uint32_t a,unsigned n)override{uint32_t v=0;for(unsigned i=0;i<n;i++)v=v<<8|bytes.at((a&0x7fffff)+i);return v;}
    void write(uint32_t a,uint32_t v,unsigned n)override{if(a>=0xc600000&&a<0xc600034)writes.push_back({a,v&uint32_t(n==1?255:65535),n});for(unsigned i=0;i<n;i++)bytes.at((a&0x7fffff)+i)=v>>((n-1-i)*8);}
};
static void require(bool ok,const char *what){if(!ok)throw std::runtime_error(what);}
int main(int argc,char**argv){try{
    if(argc!=2)return 2;Memory original,native;std::ifstream input(argv[1],std::ios::binary);require(bool(input),"Missing program");input.read((char*)original.bytes.data(),original.bytes.size());native.bytes=original.bytes;
    constexpr auto task=0xc600000;unsigned checks=0;
    for(unsigned table:{0xc28e2b0u,0xc28e2c8u,0xc28e2e0u})for(unsigned fade=0;fade<260;fade++)
    for(unsigned countdown:{0u,1u,2u,3u,20u,127u,128u,255u})for(unsigned delay:{0u,3u,20u,127u,128u,255u})for(unsigned frame:{0u,5u,6u,11u,12u,255u}){
        for(auto memory:{&original,&native}){
            for(unsigned i=0;i<0x34;i++)memory->write(task+i,0,1);
            memory->write(task+8,table,4);memory->write(task+3,frame,1);memory->write(task+4,countdown,1);memory->write(task+5,delay,1);
            memory->write(task+0x22,fade<256?fade:fade==256?32767:fade==257?32768:fade==258?65534:65535,2);
            memory->writes.clear();
        }
        futari::CompiledState state;state.bus=&original;state.pc=0xc099fe0;state.pr=0xc7ff000;state.r[4]=task;state.r[15]=0xc7fe000;
        std::vector<uint32_t> draws;unsigned steps=0;
        while(state.pc!=0xc7ff000){require(++steps<300,"Callback failed to return");
            if(state.pc==0xc063740){draws.push_back(state.r[4]);state.r[0]=0;state.pc=state.pr;}
            else futari::runCompiledOriginal(state,state.cycles+1);
        }
        auto result=futari::recovered::ParticleTrack::advance(native,task);
        require(state.r[0]==unsigned(bool(result)),"Lifetime differs");
        require(draws.size()==unsigned(bool(result)),"Draw count differs");
        if(result)require(draws[0]==result->frame&&original.read(task+0x23,1)==result->fade,"Frame/fade differs");
        require(original.writes==native.writes,"Object write order differs");
        require(std::equal(original.bytes.begin()+0x600000,original.bytes.begin()+0x600034,native.bytes.begin()+0x600000),"Object bytes differ");
        ++checks;
    }
    std::cout<<"PASS "<<checks<<" particle-track cases: three original tables, fade boundaries, signed countdown, reload, frame wrap, write order and early termination\n";
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
