#include "CompiledState.hpp"
#include <fstream>
#include <iterator>
#include <vector>
#include <cstring>
struct Memory final:futari::Bus {
    std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
    uint32_t read(uint32_t a,unsigned size) override {uint32_t v=0;for(unsigned i=0;i<size;i++)v=(v<<8)|bytes.at((a&0x7fffff)+i);return v;}
    void write(uint32_t a,uint32_t v,unsigned size) override {for(unsigned i=0;i<size;i++)bytes.at((a&0x7fffff)+i)=v>>((size-1-i)*8);}
};
int main(int argc,char **argv) {
    if(argc!=4)return 2;
    Memory memory;std::ifstream p(argv[1],std::ios::binary);p.read((char*)memory.bytes.data(),memory.bytes.size());
    std::ifstream input(argv[2],std::ios::binary),oracle(argv[3],std::ios::binary);
    uint8_t in[144],expected[140];unsigned count=0;
    while(input.read((char*)in,sizeof(in))) {
        if(!oracle.read((char*)expected,sizeof(expected)))return 3;
        auto be=[](uint8_t *v){return (uint32_t(v[0])<<24)|(uint32_t(v[1])<<16)|(uint32_t(v[2])<<8)|v[3];};
        futari::CompiledState c;c.bus=&memory;c.pc=be(in);c.r[4]=be(in+4);c.pr=0x0c7ff000;c.r[15]=0x0c7fe000;
        std::memcpy(memory.bytes.data()+0x5c468,in+8,136);
        try {futari::runCompiled(c,100000);} catch(const std::exception &e) {if(c.pc!=c.pr){fprintf(stderr,"case %u %s\n",count,e.what());return 1;}}
        if(c.pc!=c.pr||c.r[0]!=be(expected)||std::memcmp(memory.bytes.data()+0x5c468,expected+4,136)) {fprintf(stderr,"Mismatch case %u entry %08x return %08x expected %08x\n",count,be(in),c.r[0],be(expected));return 1;}
        ++count;
    }
    printf("AOT compiled input: %u cases match original registers and records exactly\n",count);
}
