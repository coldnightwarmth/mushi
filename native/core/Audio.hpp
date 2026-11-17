#pragma once
#include "../vendor/mpeg_audio.h"
#include <array>
#include <memory>
#include <vector>

namespace futari {
// Native YMZ770C sequencer/mixer, adapted from the BSD reference credited in
// THIRD_PARTY_NOTICES.md. The board connects only the right output.
class Audio {
    struct Channel {
        uint8_t phrase=0,pan=64,volume=0,loop=0;
        bool playing=false,last=false;
        int position=0,remaining=0,pointer=0,table=0;
        std::array<int16_t,4096> samples{};
        std::unique_ptr<mpeg_audio> decoder;
    };
    struct Sequence {
        uint8_t number=0,stop=0,loop=0;
        uint16_t timer=0;
        uint32_t delay=0,offset=0;
        bool playing=false;
    };
    std::shared_ptr<const std::vector<uint8_t>> rom;
    std::array<Channel,8> channels;
    std::array<Sequence,8> sequences;
    uint8_t current=0,mute=0,volume=0,boost=0,clip=0;
    uint32_t offset(unsigned table,unsigned index) const;
    void reg(uint8_t address,uint8_t value);
    void sequence();
public:
    uint64_t writes=0,rendered=0;
    explicit Audio(std::vector<uint8_t> bytes);
    Audio(const Audio &other);
    void write(unsigned port,uint8_t value);
    float sample();
};
}
