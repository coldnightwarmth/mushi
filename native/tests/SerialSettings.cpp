#include "Board.hpp"
#include <cstdio>
#include <memory>

int main(int argc,char **argv) {
    if(argc!=2)return 2;
    auto b=std::make_unique<futari::Board>(argv[1]);
    auto line=[&](unsigned v){b->write(0x10c00001,v,1);};
    auto bit=[&](unsigned v) {
        line(4|v);line(6|v);
        // Repeated writes and data changes with clock held high are not edges.
        line(6|v);line(6|(v^1));line(6|v);
    };
    auto bits=[&](unsigned value,unsigned count){while(count)bit((value>>(--count))&1);};
    for(unsigned address=0;address<256;address++) {
        line(0);line(4);bits(6,4);bits(0,12); // Write-enable, then command without CS reset.
        bits(2,4);bits(address*2,12);bits((address*257)^0xa55a,16);line(0);
    }
    for(unsigned address=0;address<256;address++) {
        line(4);bits(10,4);bits(address*2,12);
        unsigned value=0;
        for(unsigned n=0;n<16;n++){value=(value<<1)|(b->read(0x10c00001,1)&1);bit(0);}
        line(0);
        if(value!=((address*257)^0xa55a)){fprintf(stderr,"EEPROM readback failed at %u\n",address);return 1;}
    }
    puts("Serial EEPROM: all 256 words round-trip with redundant high-clock writes and continuous write-enable commands");
}
