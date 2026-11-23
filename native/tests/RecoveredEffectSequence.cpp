#include "RecoveredEffectSequence.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <set>
#include <vector>

namespace futari {void runCompiledOriginal(CompiledState &,uint64_t);}
struct Memory: futari::Bus {
    std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
    uint32_t read(uint32_t a,unsigned n)override{uint32_t v=0;for(unsigned i=0;i<n;i++)v=v<<8|bytes.at((a&0x7fffff)+i);return v;}
    void write(uint32_t a,uint32_t v,unsigned n)override{for(unsigned i=0;i<n;i++)bytes.at((a&0x7fffff)+i)=v>>((n-1-i)*8);}
};
static void require(bool ok,const char *what){if(!ok)throw std::runtime_error(what);}
int main(int argc,char **argv){try {
    if(argc!=3)return 2;Memory memory;
    std::ifstream input(argv[1],std::ios::binary);require(bool(input),"Missing expanded program");input.read((char*)memory.bytes.data(),memory.bytes.size());
    std::set<unsigned> variants;
    for(unsigned config=0;config<8;config++){
        auto pointer=memory.read(0xc2860b8+config*4,4),count=memory.read(0xc28686c+config,1);
        for(unsigned i=0;i<count;i++)variants.insert(memory.read(pointer+i*8,4));
    }
    require(variants==std::set<unsigned>{0,1,2,3},"Unexpected reachable effect variants");
    std::ofstream trace(argv[2]);trace<<"variant\ttick\tprimary\tglow\tcontinue\n";
    unsigned callbacks=0,fixtures=0;
    constexpr auto task=0xc600000;
    for(auto variant:variants)for(unsigned delay=0;delay<256;delay++){
        for(unsigned i=0;i<0xa4;i++)memory.write(task+i,0,1);
        memory.write(task+2,1,1);memory.write(task+0x78,variant,4);memory.write(task+0x71,delay,1);
        memory.write(task+8,0x640000,4);memory.write(task+12,0x780000,4);
        memory.write(task+16,0x10000,4);memory.write(task+20,0xffff8000,4);
        futari::recovered::EffectSequence8 recovered;recovered.delay=delay;
        unsigned tick=0;
        for(;;tick++){
            require(tick<2048,"Animation failed to finish");
            futari::CompiledState state;state.bus=&memory;state.pc=0xc07bf60;state.pr=0xc7ff000;state.r[15]=0xc7fe000;state.r[4]=task;
            auto expectedPrimary=recovered.primary(memory,variant),expectedGlow=recovered.glow(variant);
            bool keep=recovered.advance();std::vector<std::array<uint32_t,4>> draws;
            unsigned blocks=0;
            while(state.pc!=0xc7ff000){
                require(++blocks<1000,"Callback failed to return");
                if(state.pc==0xc063740){
                    draws.push_back({state.r[4],state.r[5],state.r[6],state.r[7]});
                    // Render submission is stubbed as unavailable. Subsequent
                    // original setters take their null-record paths. Sequence
                    // selection/countdown does not depend on a draw result.
                    state.r[0]=0;state.pc=state.pr;
                }else futari::runCompiledOriginal(state,state.cycles+1);
            }
            require(draws.size()==2&&draws[0][0]==expectedPrimary&&draws[1][0]==expectedGlow,"Frame selection differs");
            require(draws[0][3]==152&&draws[1][3]==152,"Draw priority differs");
            require(draws[0][1]==draws[1][1]+0x10000&&draws[0][2]==draws[1][2]+0xffff8000,"Layer motion offset differs");
            require(state.r[0]==unsigned(keep)&&state.r[15]==0xc7fe000,"Lifetime/stack differs");
            require(memory.read(task+0x6e,1)==recovered.frame&&memory.read(task+0x70,1)==recovered.countdown,"Countdown differs");
            if(delay==0)trace<<variant<<'\t'<<tick<<'\t'<<expectedPrimary<<'\t'<<expectedGlow<<'\t'<<keep<<'\n';
            ++callbacks;if(!keep)break;
        }
        ++fixtures;
    }
    std::cout<<"PASS "<<fixtures<<" animation fixtures / "<<callbacks<<" original callback ticks: four reachable variants, all 256 delay bytes, frame/glow IDs, offsets, countdown and completion\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
