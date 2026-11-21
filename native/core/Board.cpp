#include "Board.hpp"
#include <fstream>
#include <iterator>
#include <cstring>

namespace futari {
static std::vector<uint8_t> readFile(const std::string &path) {
    std::ifstream file(path,std::ios::binary);
    if(!file) throw std::runtime_error("Cannot read "+path);
    return {std::istreambuf_iterator<char>(file),{}};
}
Board::Board(const std::string &directory):ram(0x800000),rom(std::make_shared<const std::vector<uint8_t>>(readFile(directory+"/u4-be.bin"))),nand(std::make_shared<const std::vector<uint8_t>>(readFile(directory+"/nand.bin"))) {
    auto program=readFile(directory+"/expanded.bin");
    std::copy(program.begin(),program.end(),ram.begin());
    eeprom.fill(0xffff);state.bus=this;state.pc=0;
    audio=std::make_shared<Audio>(readFile(directory+"/sound.bin"));
}
std::unique_ptr<Board> Board::checkpoint() const {
    auto copy=std::make_unique<Board>(*this);
    copy->audio=std::make_shared<Audio>(*audio);copy->state.bus=copy.get();
    return copy;
}
uint32_t Board::ioRead(uint32_t a,unsigned size) const {
    uint32_t v=0;
    for(unsigned i=0;i<size;i++){auto it=io.find(a+i);v=(v<<8)|(it==io.end()?0:it->second);}
    return v;
}
void Board::ioWrite(uint32_t a,uint32_t v,unsigned size) {
    for(unsigned i=0;i<size;i++) io[a+i]=v>>((size-1-i)*8);
}
uint32_t Board::read(uint32_t a,unsigned size) {
    uint32_t p=a>=0xe0000000?a:a&0x1fffffff;
    const uint8_t *data=nullptr;
    if(p>=0x0c000000&&p+size<=0x0c800000) data=ram.data()+(p-0x0c000000);
    else if(p<0x400000) data=rom->data()+(p%rom->size());
    if(data) {uint32_t v=0;for(unsigned i=0;i<size;i++)v=(v<<8)|data[i];return v;}
    if(p==0x04000124) return portC;
    if(p==0x04000126) return portD;
    if(p==0x04000134) return portL;
    if(p==0x0400012a) return portF;
    if(p>=0x04000120&&p<=0x04000136) return 255;
    for(int t=0;t<3;t++) {
        uint32_t base=0xfffffe94+t*12;
        if(p==base) return timers[t].reload;
        if(p==base+4) return timers[t].count;
        if(p==base+8) return timers[t].control;
    }
    if(p==0xfffffe92) return timerStart;
    if(p==0x18000010) return 0x10;
    if(p==0x18000024||p==0x18000028) return 0xffffffff;
    if(p==0x18000050) return 0; // All four unused cabinet DIP switches default off.
    if(p==0x10c00001) return 0xfe|serialRead();
    if(p==0x10000000) {
        if(flashCommand==0x70) return 0xe0;
        if(flashCommand==0x90) {static uint8_t id[]={0xec,0xf1,0,0x15};return id[(flashID++)%4];}
        size_t offset=size_t(flashPage)*2112+flashColumn++;
        return flashColumn<=2112&&offset<nand->size()?(*nand)[offset]:255;
    }
    return ioRead(p,size);
}
void Board::write(uint32_t a,uint32_t value,unsigned size) {
    if(size<4)value&=(1u<<(size*8))-1;
    uint32_t p=a>=0xe0000000?a:a&0x1fffffff;
    if(hooks)hooks->writing(*this,p,value,size);
    if(p>=0x0c000000&&p+size<=0x0c800000) {
        for(unsigned i=0;i<size;i++) ram[p-0x0c000000+i]=value>>((size-1-i)*8);
        return;
    }
    if(p==0x10000001) {
        flashCommand=value;
        if(value==0||value==0x90||value==0x80) {flashColumn=flashPage=flashAddressCycle=flashID=0;}
        return;
    }
    if(p==0x10000002) {
        if(flashCommand==0x90) {flashID=value;return;}
        if(flashAddressCycle<2) flashColumn|=(value&255)<<(flashAddressCycle*8);
        else if(flashAddressCycle<5) flashPage|=(value&255)<<((flashAddressCycle-2)*8);
        ++flashAddressCycle;return;
    }
    if(p==0x10c00001) {serialWrite(value);return;}
    if(p>=0x10400000&&p<=0x10400007) {advanceAudio();audio->write(p&7,value);return;}
    if(p==0x18000008) {graphics.list=value;return;}
    if(p==0x18000014) {graphics.scrollX=value;return;}
    if(p==0x18000018) {graphics.scrollY=value;return;}
    if(p==0x18000040) {graphics.clipX=value;return;}
    if(p==0x18000044) {graphics.clipY=value;return;}
    if(p==0x18000004) {if(value&1)graphics.execute(*this);return;}
    if(p==0xfffffe92) {timerStart=value;return;}
    for(int t=0;t<3;t++) {
        uint32_t base=0xfffffe94+t*12;
        if(p==base) {timers[t].reload=value;return;}
        if(p==base+4) {timers[t].count=value;timers[t].remainder=0;return;}
        if(p==base+8) {timers[t].control=value;return;}
    }
    ioWrite(p,value,size);
    if(p==0x04000060||(p>=0x0400002c&&p<=0x0400005c&&(p&15)==12))dma();
}
void Board::dma() {
    if((ioRead(0x04000060,2)&7)!=1)return;
    for(unsigned channel=0;channel<4;channel++) {
        uint32_t base=0x04000020+16*channel,control=ioRead(base+12,4);
        if((control&3)!=1)continue;
        unsigned request=(control>>8)&15;
        if(request<4||request>6)continue;
        static unsigned sizes[]={1,2,4,16};unsigned size=sizes[(control>>3)&3];
        unsigned sourceMode=(control>>12)&3,destMode=(control>>14)&3;
        if(sourceMode==3||destMode==3)throw std::runtime_error("Invalid DMA address mode");
        uint32_t source=ioRead(base,4)&~(size-1),dest=ioRead(base+4,4)&~(size-1);
        uint32_t count=ioRead(base+8,4)&0xffffff;if(!count)count=0x1000000;
        for(uint32_t i=0;i<count;i++) {
            if(sourceMode==2)source-=size;if(destMode==2)dest-=size;
            if(size<=4)write(dest,read(source,size),size);
            else for(unsigned off=0;off<size;off+=4)write(dest+off,read(source+off,4),4);
            if(sourceMode==1)source+=size;if(destMode==1)dest+=size;
        }
        // Match the reference: programmed SAR/DAR remain readable unchanged;
        // completion latches TE and clears the transfer count.
        ioWrite(base+8,0,4);ioWrite(base+12,control|2,4);
    }
}
void Board::advanceAudio() {
    uint64_t target=state.cycles*16000/102400000;
    while(audio->rendered<target)audioFrame.push_back(audio->sample());
}
uint8_t Board::serialRead() const {
    if(serialMode==8||serialMode==10) return serialDataPosition>0&&serialDataPosition<=32?((serialValue>>(serialDataPosition-1))&1):0;
    return 0;
}
void Board::serialWrite(uint8_t value) {
    // Sample only rising clock edges. The output port updates data, clock,
    // then active-low reset, so this edge uses the preceding CS level.
    if((serialLines&4)&&!(serialLines&2)&&(value&2)) {
        unsigned bit=value&1;
        if(serialMode<0) {
            serialCommand=(serialCommand<<1)|bit;
            if(++serialPosition==4) {
                serialMode=serialCommand;serialPosition=serialCommand=0;
                serialAddress=serialValue=serialDataPosition=0;
            }
        } else {
            ++serialPosition;
            unsigned addressBits=(serialMode==2||serialMode==10)?12:4;
            unsigned dataBits=addressBits==12?16:8;
            if(serialMode==6) {if(serialPosition==12){serialPosition=0;serialMode=-1;}}
            else if(serialPosition<=addressBits) {
                serialAddress=(serialAddress<<1)|bit;
                if(serialPosition==addressBits&&(serialMode==8||serialMode==10)) {
                    serialValue=serialMode==10?eeprom[(serialAddress>>1)&255]:rtc[serialAddress&7];
                    serialDataPosition=dataBits;
                }
            } else if(serialMode==8||serialMode==10) {
                if(serialDataPosition) --serialDataPosition;
                if(serialPosition==addressBits+dataBits) serialPosition=0;
            } else {
                serialValue=(serialValue<<1)|bit;
                if(serialPosition==addressBits+dataBits) {
                    if(serialMode==2)eeprom[(serialAddress>>1)&255]=serialValue;
                    else if(serialMode==0)rtc[serialAddress&7]=serialValue;
                    serialMode=-1;serialPosition=0;
                }
            }
        }
    }
    if((serialLines&4)&&!(value&4)) {serialMode=-1;serialCommand=serialPosition=serialAddress=serialValue=serialDataPosition=0;}
    serialLines=value;
}
void Board::advanceTimers(uint64_t instructions) {
    // SH3 peripheral clock is CPU/4. Native instruction accounting is refined
    // against frame traces independently from the wall-clock presentation rate.
    static unsigned divisors[]={4,16,64,256,1024,1,1,1};
    for(int i=0;i<3;i++) if(timerStart&(1<<i)) {
        auto &t=timers[i];unsigned divisor=4*divisors[t.control&7];
        t.remainder+=instructions;uint64_t ticks=t.remainder/divisor;t.remainder%=divisor;
        if(ticks>t.count) {
            ticks-=uint64_t(t.count)+1;t.control|=0x100;
            t.count=t.reload-(ticks%(uint64_t(t.reload)+1));
        } else t.count-=ticks;
    }
}
void Board::interrupt() {
    if(state.sr&0x10000000) return;
    unsigned priority=0,event=0;
    if(vblankPending) {priority=(ioRead(0x04000016,2)>>8)&15;event=0x640;}
    uint32_t ipra=ioRead(0xfffffee2,2);
    for(int i=0;i<3;i++) if((timers[i].control&0x120)==0x120) {
        unsigned p=(ipra>>(12-i*4))&15;
        if(p>priority) {priority=p;event=0x400+i*0x20;}
    }
    if(priority<=((state.sr>>4)&15)) return;
    if(event==0x640) vblankPending=false;
    ioWrite(0x04000000,event,4);
    ioWrite(0xffffffd8,event>=0x600?0x3e0-priority*0x20:event,4);
    state.ssr=state.sr;state.spc=state.pc;state.status(state.sr|0x70000000);
    state.pc=state.vbr+0x600;++interrupts;
}
void Board::frame() {
    audioFrame.clear();
    const uint64_t end=(frameNumber+1)*1706144; // 102.4 MHz / board raster rate.
    vblankPending=true;
    while(state.cycles<end) {
        interrupt();uint64_t before=state.cycles;
        runCompiled(state,std::min(end,before+2048));
        advanceTimers(state.cycles-before);
    }
    ++frameNumber;
    advanceAudio();
}
}
