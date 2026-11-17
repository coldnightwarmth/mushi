#include "Graphics.hpp"
#include <fstream>
#include <iterator>
struct Memory final:futari::Bus {
    std::vector<uint8_t> bytes;
    uint32_t read(uint32_t a,unsigned size) override {uint32_t v=0;for(unsigned i=0;i<size;i++)v=(v<<8)|bytes.at(a+i);return v;}
    void write(uint32_t,uint32_t,unsigned) override {throw std::runtime_error("Unexpected write");}
};
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    Memory m;std::ifstream in(argv[1],std::ios::binary);m.bytes={std::istreambuf_iterator<char>(in),{}};
    futari::Graphics g;g.list=8;g.clipX=m.read(0,4);g.clipY=m.read(4,4);g.execute(m);
    std::ofstream(argv[2],std::ios::binary).write((char*)g.pixels.data(),g.pixels.size()*4);
}
