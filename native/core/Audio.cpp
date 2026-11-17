#include "Audio.hpp"
#include <algorithm>

namespace futari {
Audio::Audio(std::vector<uint8_t> bytes):rom(std::make_shared<const std::vector<uint8_t>>(std::move(bytes))) {
    for(auto &c:channels)c.decoder=std::make_unique<mpeg_audio>(rom->data(),mpeg_audio::AMM,false,0);
}
Audio::Audio(const Audio &o):rom(o.rom),sequences(o.sequences),current(o.current),mute(o.mute),volume(o.volume),boost(o.boost),clip(o.clip),writes(o.writes),rendered(o.rendered) {
    for(unsigned i=0;i<channels.size();i++) {
        auto &c=channels[i];const auto &s=o.channels[i];
        c.phrase=s.phrase;c.pan=s.pan;c.volume=s.volume;c.loop=s.loop;c.playing=s.playing;c.last=s.last;
        c.position=s.position;c.remaining=s.remaining;c.pointer=s.pointer;c.table=s.table;c.samples=s.samples;
        c.decoder=std::make_unique<mpeg_audio>(*s.decoder);
    }
}
uint32_t Audio::offset(unsigned table,unsigned index) const {
    unsigned p=table+index*4;
    return (uint32_t(rom->at(p+1))<<16)|(uint32_t(rom->at(p+2))<<8)|rom->at(p+3);
}
void Audio::write(unsigned port,uint8_t value) {
    ++writes;
    if(port&1)reg(current,value);else current=value;
}
void Audio::reg(uint8_t address,uint8_t value) {
    if(address<0x40) {
        if(address==0)mute=value&1;
        if(address==1)volume=value;
        if(address==2){boost=value&7;clip=(value>>4)&7;}
    } else if(address<0x60) {
        auto &c=channels[(address>>2)&7];
        switch(address&3) {
        case 0:c.phrase=value;break;
        case 1:c.volume=value;break;
        case 2:c.pan=value<<3;break;
        case 3:
            if((value&6)==2||((value&6)==6&&!c.playing)) {
                c.table=((*rom)[c.phrase*4]>>4)&7;c.position=offset(0,c.phrase)*8;
                c.last=false;c.playing=true;
            } else if((value&6)==0)c.playing=false;
            c.loop=(value&1)?255:0;break;
        }
    } else if(address>=0x80) {
        auto &s=sequences[(address>>4)&7];
        switch(address&15) {
        case 0:s.number=value;break;
        case 1:
            if((value&6)==2||((value&6)==6&&!s.playing)) {
                s.offset=offset(0x400,s.number);s.delay=0;s.playing=true;
            } else if((value&6)==0&&s.playing) {
                s.playing=false;for(int i=0;i<8;i++)if(s.stop&(1<<i))channels[i].playing=false;
            }
            s.loop=value&1;break;
        case 2:s.timer=(s.timer&255)|(value<<8);break;
        case 3:s.timer=(s.timer&0xff00)|value;break;
        case 6:s.stop=value;break;
        }
    }
}
void Audio::sequence() {
    for(auto &s:sequences)if(s.playing) {
        if(s.delay){--s.delay;continue;}
        uint8_t address=(*rom)[(s.offset++)%rom->size()],value=(*rom)[(s.offset++)%rom->size()];
        if(address==15) {
            for(int i=0;i<8;i++)if(s.stop&(1<<i))channels[i].playing=false;
            if(s.loop)s.offset=offset(0x400,s.number);else s.playing=false;
        } else if(address==14)s.delay=s.timer*32+31;
        else reg(address,value);
    }
}
float Audio::sample() {
    ++rendered;sequence();int32_t mix=0;
    for(auto &c:channels) {
        if(c.remaining==0&&c.playing) {
            // At most two attempts: malformed/empty looping phrases stop.
            for(unsigned attempts=0;attempts<2&&c.remaining==0&&c.playing;attempts++) {
                if(c.last) {
                    if(c.loop) {
                        if(c.loop!=255)--c.loop;
                        c.table=((*rom)[c.phrase*4]>>4)&7;c.position=offset(0,c.phrase)*8;
                    } else {c.playing=false;c.decoder->clear();break;}
                }
                int rate,count;
                if(!c.decoder->decode_buffer(c.position,int(rom->size()*8),c.samples.data(),c.remaining,rate,count,c.table)||!c.remaining) {
                    c.playing=!c.last;c.last=true;c.remaining=0;continue;
                }
                c.last=c.remaining<1152;c.pointer=0;
            }
        }
        if(c.remaining>0) {
            int32_t value=(int32_t(c.samples[c.pointer++])*c.volume)>>7;
            mix+=(value*c.pan)>>7;
            if(--c.remaining==0&&!c.playing)c.decoder->clear();
        }
    }
    mix=(mix*volume)>>(7-boost);
    if(clip==1)mix=std::clamp(mix,-32768,32767);
    else if(clip==2)mix=std::clamp(mix,-28672,28672);
    else if(clip==3)mix=std::clamp(mix,-24576,24576);
    return mute?0:float(mix)/32768.f;
}
}
