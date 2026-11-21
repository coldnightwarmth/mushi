#include "Board.hpp"
#include <cstdio>
#include <fstream>
#include <chrono>
#include <memory>
#include <map>

int main(int argc,char **argv) {
    if(argc<2){fprintf(stderr,"Usage: NativeBoot resource-directory [frames] [output-prefix]\n");return 2;}
    auto b=std::make_unique<futari::Board>(argv[1]);
    unsigned frames=argc>2?std::stoul(argv[2]):600;
    std::string prefix=argc>3?argv[3]:"build/aot/boot";
    std::map<unsigned,std::pair<unsigned,unsigned>> events;
    if(argc>4) {std::ifstream replay(argv[4]);unsigned f,c,d;while(replay>>f>>c>>d)events[f]={c,d};}
    auto snapshot=[&](const std::string &name) {
        std::vector<uint8_t> rgba(240*320*4);b->graphics.rgba(rgba.data());
        std::ofstream(name+".rgba",std::ios::binary).write((char*)rgba.data(),rgba.size());
    };
    std::ofstream audio(prefix+".f32",std::ios::binary);
    auto start=std::chrono::steady_clock::now();
    uint32_t previousRoot=~0u,previousPlay=~0u,previousStage=~0u;
    try {
        for(unsigned f=0;f<frames;f++) {
            auto event=events.find(f);if(event!=events.end()){b->portC=event->second.first;b->portD=event->second.second;}
            b->frame();
            auto root=b->read(0x0c38a4b4,4),play=b->read(0x0c38a578,2),stage=b->read(0x0c38a586,2);
            if(root!=previousRoot||play!=previousPlay||stage!=previousStage) {
                fprintf(stderr,"scene frame=%u root=%u play=%u stage=%u\n",f,root,play,stage);
                previousRoot=root;previousPlay=play;previousStage=stage;
                snapshot(prefix+"-scene-"+std::to_string(f));
                std::ofstream(prefix+"-scene-"+std::to_string(f)+".ram",std::ios::binary).write((char*)b->ram.data(),b->ram.size());
            }
            audio.write((char*)b->audioFrame.data(),b->audioFrame.size()*sizeof(float));
            if(f%300==0) {fprintf(stderr,"frame %u pc=%08x sr=%08x irq=%llu lists=%llu draws=%llu uploads=%llu scroll=%u,%u\n",f,b->state.pc,b->state.sr,b->interrupts,b->graphics.lists,b->graphics.draws,b->graphics.uploads,b->graphics.scrollX,b->graphics.scrollY);snapshot(prefix+"-"+std::to_string(f));}
        }
    } catch(const std::exception &e) {
        fprintf(stderr,"%s, frame=%llu pc=%08x pr=%08x sr=%08x cycles=%llu\n",e.what(),b->frameNumber,b->state.pc,b->state.pr,b->state.sr,b->state.cycles);
        for(int i=0;i<16;i++)fprintf(stderr,"R%d=%08x%c",i,b->state.r[i],i%4==3?'\n':' ');
        std::ofstream(prefix+".ram",std::ios::binary).write((char*)b->ram.data(),b->ram.size());
        return 1;
    }
    snapshot(prefix);
    std::ofstream(prefix+".ram",std::ios::binary).write((char*)b->ram.data(),b->ram.size());
    fprintf(stderr,"Completed %u frames in %.3f seconds\n",frames,std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());
}
