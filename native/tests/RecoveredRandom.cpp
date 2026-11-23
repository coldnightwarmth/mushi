#include "RecoveredRandom.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <vector>
namespace futari {void runCompiledOriginal(CompiledState &,uint64_t);}
struct Memory: futari::Bus {
    std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
    std::vector<std::array<uint32_t,3>> writes;
    uint32_t read(uint32_t a,unsigned n)override{uint32_t v=0;for(unsigned i=0;i<n;i++)v=v<<8|bytes.at((a&0x7fffff)+i);return v;}
    void write(uint32_t a,uint32_t v,unsigned n)override{if(a<0xc700000)writes.push_back({a,v,n});for(unsigned i=0;i<n;i++)bytes.at((a&0x7fffff)+i)=v>>((n-1-i)*8);}
};
int main(int argc,char**argv){try{
    if(argc!=2)return 2;Memory original,native;std::ifstream input(argv[1],std::ios::binary);if(!input)throw std::runtime_error("Missing program");input.read((char*)original.bytes.data(),original.bytes.size());native.bytes=original.bytes;
    unsigned cases=0;
    for(unsigned bound=0;bound<32768;bound++)for(uint32_t seed:{0u,1u,0xffffffffu,0x12345678u}){
        original.write(futari::recovered::Random::seedAddress,seed,4);native.write(futari::recovered::Random::seedAddress,seed,4);original.writes.clear();native.writes.clear();
        futari::CompiledState state;state.bus=&original;state.pc=0xc0631f0;state.pr=0xc7ff000;state.r[4]=bound;state.r[15]=0xc7fe000;
        unsigned blocks=0;while(state.pc!=0xc7ff000){if(++blocks>500)throw std::runtime_error("Random routine did not return");futari::runCompiledOriginal(state,state.cycles+1);}
        auto value=futari::recovered::Random::next(native,bound);
        if(value!=state.r[0]||original.writes!=native.writes||original.read(futari::recovered::Random::seedAddress,4)!=native.read(futari::recovered::Random::seedAddress,4))throw std::runtime_error("Random value, seed or write differs");
        ++cases;
    }
    std::cout<<"PASS "<<cases<<" RNG cases: every nonnegative signed-16 inclusive bound, four seed boundaries, exact values/seed/writes, zero-bound non-advancement\n";
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
