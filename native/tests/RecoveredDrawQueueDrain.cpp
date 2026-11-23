#include "RecoveredDrawQueueDrain.hpp"
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
static void require(bool ok,const char *what){if(!ok)throw std::runtime_error(what);}
int main(int argc,char **argv){try{
    if(argc!=2)return 2;Memory seed,original,recovered;
    std::ifstream input(argv[1],std::ios::binary);require(bool(input),"Missing program");input.read((char*)seed.bytes.data(),seed.bytes.size());
    uint32_t random=0x15e1a77;auto next=[&](){random^=random<<13;random^=random>>17;random^=random<<5;return random;};
    unsigned callbacks=0;
    for(unsigned fixture=0;fixture<516;fixture++){
        original.bytes=seed.bytes;
        original.write(0xc058338,0xc600000,4);original.write(0xc05833c,0,4);
        for(unsigned i=0;i<512*8;i++)original.write(0xc058340+i,0,1);
        for(unsigned i=0;i<0x17700;i++)original.write(0xc600000+i,0,1);
        for(unsigned priority=0;priority<512;priority++){
            auto count=fixture<512 ? (priority==fixture?3u:0u):next()%5;
            for(unsigned n=0;n<count;n++)futari::recovered::DrawQueue::append(original,0xc7fd000,priority*256+n,priority);
        }
        recovered.bytes=original.bytes;original.writes.clear();recovered.writes.clear();
        std::vector<std::array<uint32_t,2>> a,b;
        auto callback=[&](Memory &memory,std::vector<std::array<uint32_t,2>> &calls,uint32_t function,uint32_t payload){
            require(function==0xc7fd000,"Unexpected callback");calls.push_back({function,payload});
            if(fixture>=513&&calls.size()==1){
                unsigned target=fixture==513?0:fixture==514?510:511;
                futari::recovered::DrawQueue::append(memory,0xc7fd000,0x80000000|fixture,target);
            }
        };
        futari::CompiledState state;state.bus=&original;state.pc=0xc05c3ec;state.pr=0xc7ff000;state.r[15]=0xc7fe000;
        unsigned steps=0;
        while(state.pc!=0xc7ff000){
            require(++steps<50000,"Drain did not return");
            if(state.pc==0xc7fd000){callback(original,a,state.pc,state.r[4]);state.pc=state.pr;}
            else if(state.pc==0xc0512bc||state.pc==0xc0512e4||state.pc==0xc05dd00){state.r[0]=0;state.pc=state.pr;}
            else futari::runCompiledOriginal(state,state.cycles+1);
        }
        auto count=futari::recovered::drainDrawQueue(recovered,[&](uint32_t function,uint32_t payload){callback(recovered,b,function,payload);});
        require(count==b.size()&&a==b,"Callback order differs");
        require(original.writes==recovered.writes,"Queue write order differs");
        require(std::equal(original.bytes.begin(),original.bytes.begin()+0x700000,recovered.bytes.begin()),"Queue RAM differs");
        if(fixture==511)require(a.empty(),"Reserved priority bucket must not execute");
        callbacks+=a.size();
    }
    std::cout<<"PASS 516 queue-drain fixtures / "<<callbacks<<" callbacks: FIFO order, every priority, reserved bucket 511, callback appends, exact queue RAM and ordered writes\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
