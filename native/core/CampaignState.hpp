#pragma once
#include "CompiledState.hpp"

namespace futari {
enum class CampaignPhase {
    Startup=0, Attract=1, Selection=2, Playing=3, Operator=4,
    Ending=5, GameOver=6, Ranking=7, Transition=8
};
// Recovered from the paid-game dispatcher at 0x0c067a70 and its state-4
// callback at 0x0c0694e0. This view reads state; it never advances the game.
struct CampaignState {
    static constexpr uint32_t context=0x0c38a530;
    static constexpr int stageCount=5;
    uint32_t root=0,play=0,substate=0;
    int stage=-1,mode=-1;
    bool allClear=false;
    CampaignPhase phase=CampaignPhase::Startup;
    static CampaignState read(Bus &memory) {
        CampaignState s;
        s.root=memory.read(0x0c38a4b4,4);
        if(s.root==3)s.phase=CampaignPhase::Attract;
        else if(s.root==6)s.phase=CampaignPhase::Operator;
        else if(s.root==5) {
            s.play=memory.read(context+0x48,2);
            s.substate=memory.read(context+0x4a,2);
            s.mode=int(memory.read(context+0x50,4));
            s.stage=int(memory.read(context+0x56,2));
            s.allClear=memory.read(context+0x144,2)!=0;
            switch(s.play) {
                case 0:case 1:case 2:s.phase=CampaignPhase::Selection;break;
                case 4:s.phase=CampaignPhase::Playing;break;
                case 5:s.phase=CampaignPhase::GameOver;break;
                case 6:s.phase=CampaignPhase::Ranking;break;
                case 7:s.phase=CampaignPhase::Ending;break;
                default:s.phase=CampaignPhase::Transition;break;
            }
        } else if(s.root>1)s.phase=CampaignPhase::Transition;
        return s;
    }
};
}
