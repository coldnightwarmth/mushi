#include "RecoveredParticleInit.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <set>
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
static void invoke(futari::CompiledState &state) {
    unsigned steps=0;
    while(state.pc!=0xc7ff000) {
        require(++steps<2000,"Routine did not return");
        futari::runCompiledOriginal(state,state.cycles+1);
    }
}
int main(int argc,char **argv) {try {
    if(argc!=2)return 2;
    Memory original,native;
    std::ifstream input(argv[1],std::ios::binary);
    require(bool(input),"Missing program");
    input.read((char*)original.bytes.data(),original.bytes.size());native.bytes=original.bytes;
    constexpr uint32_t task=0xc600000;
    unsigned polarCases=0,initCases=0;
    for(unsigned angle=0;angle<1024;angle++)
    for(uint32_t speed:{0u,1u,8u,134u,0x7fffffffu,0x80000000u,0xffffffffu})
    for(unsigned destinations=0;destinations<4;destinations++) {
        const auto x=destinations&1?task:0,y=destinations&2?task+4:0;
        original.writes.clear();native.writes.clear();
        futari::CompiledState state;state.bus=&original;state.pc=0xc063680;
        state.pr=0xc7ff000;state.r[15]=0xc7fe000;
        state.r[4]=speed;state.r[5]=angle;state.r[6]=x;state.r[7]=y;invoke(state);
        futari::recovered::PolarVelocity::write(native,speed,angle,x,y);
        require(original.writes==native.writes,"Polar component writes differ");++polarCases;
    }
    std::set<std::array<uint32_t,4>> choices;
    for(unsigned slow=0;slow<2;slow++)for(unsigned flags:{0u,4u})
    for(unsigned spread:{0u,1u,64u,255u,512u,32767u})
    for(unsigned angle:{0u,1u,511u,512u,65535u})for(unsigned seed=0;seed<1024;seed++) {
        for(auto memory:{&original,&native}) {
            for(unsigned i=0;i<0x34;i++)memory->write(task+i,(seed+i)*13,1);
            memory->write(task,flags,1);memory->write(task+0x20,angle,2);
            memory->write(task+0x26,spread,2);
            memory->write(futari::recovered::Random::seedAddress,seed*0x9e3779b9u,4);
            memory->writes.clear();
        }
        futari::CompiledState state;state.bus=&original;state.pc=slow?0xc099ef0:0xc099e00;
        state.pr=0xc7ff000;state.r[15]=0xc7fe000;state.r[4]=task;invoke(state);
        futari::recovered::ParticleInit::initialize(native,task,slow);
        require(state.r[0]==1,"Initializer return differs");
        require(original.writes==native.writes,"Initializer write order/value differs");
        require(std::equal(original.bytes.begin()+0x600000,original.bytes.begin()+0x600034,
                           native.bytes.begin()+0x600000),"Initialized object differs");
        choices.insert({slow,original.read(task+0x22,2),original.read(task+8,4),
                        original.read(task+0x24,2)==1});++initCases;
    }
    require(choices.size()==2*17*3*2,"Initializer random choices not all reached");
    std::cout<<"PASS "<<polarCases<<" polar-velocity cases: angle wrap, overflow, optional destinations and write order\n";
    std::cout<<"PASS "<<initCases<<" particle initializers: two types, preserve/random velocity, six spreads, five angles, 1024 seeds; every fade/table/flip combination reached\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
