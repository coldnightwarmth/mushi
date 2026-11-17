#pragma once
#include "Graphics.hpp"
#include "Audio.hpp"
#include <array>
#include <unordered_map>
#include <vector>

namespace futari {
struct Board final : Bus {
    CompiledState state;
    Graphics graphics;
    std::vector<uint8_t> ram;
    std::shared_ptr<const std::vector<uint8_t>> rom,nand;
    std::shared_ptr<Audio> audio;
    std::vector<float> audioFrame;
    std::unordered_map<uint32_t,uint8_t> io;
    uint8_t portC=255,portD=255,portF=255;
    uint32_t flashCommand=0,flashColumn=0,flashPage=0,flashAddressCycle=0,flashID=0;
    uint32_t serialCommand=0,serialPosition=0,serialAddress=0,serialValue=0,serialDataPosition=0;
    int serialMode=-1;uint8_t serialLines=0;
    std::array<uint16_t,256> eeprom;
    std::array<uint8_t,8> rtc{{0,0,12,1,1,1,0x26,0x20}};
    bool vblankPending=false;
    uint64_t frameNumber=0,interrupts=0;
    struct Timer {uint32_t count=0xffffffff,reload=0xffffffff,control=0;uint64_t remainder=0;};
    Timer timers[3];uint8_t timerStart=0;
    Board(const std::string &directory);
    std::unique_ptr<Board> checkpoint() const;
    uint32_t read(uint32_t address,unsigned size) override;
    void write(uint32_t address,uint32_t value,unsigned size) override;
    void frame();
    void advanceTimers(uint64_t instructions);
    void interrupt();
    void serialWrite(uint8_t value);
    void dma();
    void advanceAudio();
    uint8_t serialRead() const;
    uint32_t ioRead(uint32_t address,unsigned size) const;
    void ioWrite(uint32_t address,uint32_t value,unsigned size);
};
}
