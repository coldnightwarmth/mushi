#include "Board.hpp"
#include "CampaignState.hpp"
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <set>

namespace futari {void runCompiledOriginal(CompiledState &,uint64_t);}
static void originalFrame(futari::Board &board) {
    board.audioFrame.clear();const auto end=(board.frameNumber+1)*1706144;
    board.vblankPending=true;
    while(board.state.cycles<end){
        board.interrupt();auto before=board.state.cycles;
        futari::runCompiledOriginal(board.state,std::min(end,before+2048));
        board.advanceTimers(board.state.cycles-before);
    }
    ++board.frameNumber;board.advanceAudio();
}
static bool same(const futari::CompiledState &a,const futari::CompiledState &b) {
    return !std::memcmp(a.r,b.r,sizeof(a.r))&&!std::memcmp(a.bank,b.bank,sizeof(a.bank))&&
        a.pc==b.pc&&a.sr==b.sr&&a.pr==b.pr&&a.gbr==b.gbr&&a.vbr==b.vbr&&a.mach==b.mach&&a.macl==b.macl&&
        a.ssr==b.ssr&&a.spc==b.spc&&a.cycles==b.cycles&&a.deadline==b.deadline;
}
int main(int argc,char **argv){try {
    if(argc!=3){std::cerr<<"RecoveredReplay resources menu-inputs.tsv\n";return 2;}
    futari::Board native(argv[1]),original(argv[1]);
    std::ifstream input(argv[2]);std::map<unsigned,std::pair<unsigned,unsigned>> events;
    unsigned f,c,d;while(input>>f>>c>>d)events[f]={c,d};c=d=255;
    bool ending=false;std::set<int> stages;unsigned vramChecks=0;
    for(f=0;f<180000;f++){
        auto before=futari::CampaignState::read(original);
        if(events.count(f)){c=events[f].first;d=events[f].second;}
        if(f>=3300){
            c=255;d=191;
            if(f>=3700){auto phase=(f-3700)%180;if(phase<12)c&=~4;if(phase>=30&&phase<42)c&=~16;}
            if(f>=3500&&(f-3500)%240<12)d&=~32;
        }
        if(ending){c=d=255;if(before.phase==futari::CampaignPhase::Ranking&&f%90<3)d=239;}
        native.portC=original.portC=c;native.portD=original.portD=d;
        native.frame();originalFrame(original);
        if(!same(native.state,original.state)||native.ram!=original.ram||native.io!=original.io||native.audioFrame!=original.audioFrame||native.interrupts!=original.interrupts)
            throw std::runtime_error("Native/original state, RAM, IO, audio or interrupt divergence at frame "+std::to_string(f));
        auto state=futari::CampaignState::read(native);
        bool newStage=state.phase==futari::CampaignPhase::Playing&&stages.insert(state.stage).second;
        if(f%120==0||newStage){
            if(native.graphics.pixels!=original.graphics.pixels)throw std::runtime_error("VRAM divergence at frame "+std::to_string(f));
            ++vramChecks;
        }
        if(newStage)std::cout<<"Stage "<<state.stage+1<<" exact at frame "<<f<<std::endl;
        if(state.play==7&&state.allClear)ending=true;
        if(ending&&state.root==3){
            if(stages.size()!=5)throw std::runtime_error("Missing stage");
            if(native.graphics.pixels!=original.graphics.pixels)throw std::runtime_error("Final VRAM mismatch");
            std::cout<<"PASS "<<f+1<<" native/original frames: all registers, instruction counts, RAM, IO, audio and interrupt counts exact; "<<vramChecks+1<<" complete VRAM comparisons; five stages, ending and attract\n";
            return 0;
        }
        if(f%6000==0)std::cout<<"Compared "<<f<<" frames"<<std::endl;
    }
    throw std::runtime_error("Full campaign did not finish");
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
