#include "RecoveredParticleInit.hpp"
#include "RecoveredParticleTrack.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <map>
#include <vector>

namespace futari { void runCompiledOriginal(CompiledState &,uint64_t); }
struct Memory: futari::Bus {
    std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
    std::vector<std::array<uint32_t,3>> writes;
    uint32_t read(uint32_t a,unsigned n) override {
        uint32_t v=0;for(unsigned i=0;i<n;i++)v=v<<8|bytes.at((a&0x7fffff)+i);return v;
    }
    void write(uint32_t a,uint32_t v,unsigned n) override {
        if(a<0xc700000)writes.push_back({a,v&(n==4?0xffffffffu:n==2?65535u:255u),n});
        for(unsigned i=0;i<n;i++)bytes.at((a&0x7fffff)+i)=v>>((n-1-i)*8);
    }
};
static void require(bool condition,const char *message) {
    if(!condition)throw std::runtime_error(message);
}
int main(int argc,char **argv) {try {
    if(argc!=3)return 2;
    Memory original,native;
    std::ifstream input(argv[1],std::ios::binary);require(bool(input),"Missing program");
    input.read((char*)original.bytes.data(),original.bytes.size());native.bytes=original.bytes;
    constexpr uint32_t task=0xc600000;
    using Choice=std::array<uint32_t,3>;
    std::map<Choice,uint32_t> seeds;
    for(uint32_t seed=0;seeds.size()<17*3*2;seed++) {
        require(seed<65536,"Could not reach all particle choices");
        native.write(futari::recovered::Random::seedAddress,seed,4);
        auto fade=255u-futari::recovered::Random::next(native,16);
        auto table=futari::recovered::Random::next(native,2);
        auto flip=futari::recovered::Random::next(native,1);
        seeds.emplace(Choice{fade,table,flip},seed);
        native.writes.clear();
    }
    std::ofstream trace(argv[2]);require(bool(trace),"Cannot create trace");
    trace<<"type\ttable\tinitial_fade\tflip\tseed\ttick\tframe\tfade\tcontinue\n";
    unsigned fixtures=0,ticks=0,draws=0;
    for(unsigned type:{0u,5u})for(const auto &entry:seeds) {
        const auto choice=entry.first;
        const auto seed=entry.second;
        for(auto memory:{&original,&native}) {
            for(unsigned i=0;i<0x34;i++)memory->write(task+i,0,1);
            memory->write(task,4,1);memory->write(task+2,type,1);
            memory->write(task+12,100<<16,4);memory->write(task+16,120<<16,4);
            memory->write(task+0x1c,153,2);
            memory->write(futari::recovered::Random::seedAddress,seed,4);memory->writes.clear();
        }
        auto invoke=[&](uint32_t address) {
            futari::CompiledState state;state.bus=&original;state.pc=address;
            state.pr=0xc7ff000;state.r[15]=0xc7fe000;state.r[4]=task;
            unsigned blocks=0,submissions=0,flips=0,blends=0;
            uint32_t frame=0;
            while(state.pc!=0xc7ff000) {
                require(++blocks<2000,"Particle callback failed to return");
                if(state.pc==0xc063740) {
                    require(state.r[5]==100u<<16&&state.r[6]==120u<<16&&state.r[7]==153,"Position/priority changed");
                    frame=state.r[4];++submissions;state.r[0]=0;state.pc=state.pr;
                } else {
                    if(state.pc==0xc05e2d8) {require(state.r[4]==0&&state.r[5]==choice[2],"Flip arguments differ");++flips;}
                    if(state.pc==0xc05e424) {
                        require(state.r[4]==0&&state.r[5]==2&&state.r[6]==1&&
                                state.r[7]==original.read(task+0x23,1)&&original.read(state.r[15],4)==0,"Blend arguments differ");++blends;
                    }
                    futari::runCompiledOriginal(state,state.cycles+1);
                }
            }
            require(submissions==flips&&submissions==blends,"Submission/setter counts differ");
            return std::array<uint32_t,3>{state.r[0],submissions,frame};
        };
        require(invoke(type==5?0xc099ef0:0xc099e00)[0]==1,"Initializer failed");
        futari::recovered::ParticleInit::initialize(native,task,type==5);
        require(original.writes==native.writes,"Initializer differs");
        for(unsigned tick=0;;tick++) {
            require(tick<128,"Track failed to finish");
            original.writes.clear();native.writes.clear();
            const auto result=invoke(0xc099fe0);
            const auto expected=futari::recovered::ParticleTrack::advance(native,task);
            require(result[0]==unsigned(bool(expected))&&result[1]==unsigned(bool(expected)),"Lifetime/draw count differs");
            if(expected)require(result[2]==expected->frame&&original.read(task+0x23,1)==expected->fade,"Frame/fade differs");
            require(original.writes==native.writes,"Track writes differ");
            require(std::equal(original.bytes.begin()+0x600000,original.bytes.begin()+0x600034,
                               native.bytes.begin()+0x600000),"Track object differs");
            trace<<type<<'\t'<<choice[1]<<'\t'<<choice[0]<<'\t'<<choice[2]<<'\t'<<seed<<'\t'<<tick<<'\t'
                 <<result[2]<<'\t'<<original.read(task+0x22,2)<<'\t'<<result[0]<<'\n';
            ++ticks;draws+=result[1];if(!expected)break;
        }
        ++fixtures;
    }
    std::cout<<"PASS "<<fixtures<<" complete particle tracks / "<<ticks<<" update ticks / "<<draws
             <<" draws: every reachable fade/table/flip for types 0 and 5, original RNG, initializer, frame timing, blend arguments and termination\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
