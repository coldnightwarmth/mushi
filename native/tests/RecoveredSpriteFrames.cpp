#include "RecoveredSpriteFrames.hpp"
#include "NativeInspection.hpp"
#include <fstream>
#include <iostream>
#include <vector>

struct Memory: futari::Bus {
    std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
    uint32_t read(uint32_t a,unsigned n) override {
        uint32_t v=0;for(unsigned i=0;i<n;i++)v=v<<8|bytes.at((a&0x7fffff)+i);return v;
    }
    void write(uint32_t a,uint32_t v,unsigned n) override {
        for(unsigned i=0;i<n;i++)bytes.at((a&0x7fffff)+i)=v>>((n-1-i)*8);
    }
};
static void require(bool ok,const char *what){if(!ok)throw std::runtime_error(what);}
int main(int argc,char **argv){try {
    if(argc!=3){std::cerr<<"RecoveredSpriteFrames expanded.bin resources\n";return 2;}
    Memory memory;std::ifstream file(argv[1],std::ios::binary);
    require(bool(file),"Cannot read expanded program");file.read((char*)memory.bytes.data(),memory.bytes.size());
    const auto count=memory.read(futari::recovered::SpriteFrame::countAddress,4);
    require(count==49589,"Unexpected frame count");
    uint32_t random=0xf15a0321;auto next=[&](){random^=random<<13;random^=random>>17;random^=random<<5;return random;};
    for(uint32_t index=0;index<count+4;index++){
        uint32_t id=index<count?index:index==count?count:index==count+1?count+1:index==count+2?0x80000000:0xffffffff;
        futari::CompiledState state;state.bus=&memory;state.pc=0xc063740;state.pr=0xc7ff000;
        for(auto &r:state.r)r=next();state.r[4]=id;state.r[15]=0xc7fe000;
        auto x=state.r[5],y=state.r[6],priority=state.r[7];
        auto frame=futari::recovered::SpriteFrame::read(memory,id);
        unsigned steps=0;
        while(state.pc!=0xc05df30&&state.pc!=0xc7ff000){
            require(++steps<100,"Frame wrapper did not terminate");
            futari::runCompiled(state,state.cycles+1);
        }
        if(!frame){require(state.pc==state.pr&&state.r[0]==0&&state.r[15]==0xc7fe000,"Invalid frame not rejected");continue;}
        require(state.pc==0xc05df30,"Valid frame not submitted");
        require(frame->id==id&&frame->width&&frame->height&&frame->x+frame->width<=256&&frame->y+frame->height<=256,"Invalid descriptor");
        require(state.r[4]==frame->resource,"Resource mapping differs");
        auto arguments=frame->drawArguments(x,y,priority);
        for(unsigned i=0;i<arguments.size();i++)require(memory.read(state.r[5]+i*4,4)==arguments[i],"Draw coordinate differs from original wrapper");
    }
    std::cout<<"PASS "<<count<<" frame descriptors and four out-of-range IDs against original drawing wrapper\n";
    // The loader's resource ID indexes a direct copy of the NAND directory.
    // Verify that identity through the running native board, not a guessed name.
    futari::Board board(argv[2]);for(unsigned i=0;i<1200;i++)board.frame();
    auto directory=board.read(0xc32033c,4),entries=board.read(0xc320338,4);
    require(entries==1201,"Native directory count differs");
    for(unsigned i=0;i<entries*16;i++)require(board.read(directory+i,1)==board.nand->at(2112+i),"Native resource IDs differ from NAND directory");
    std::cout<<"PASS "<<entries<<" native resource-directory entries match NAND indices byte for byte\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
