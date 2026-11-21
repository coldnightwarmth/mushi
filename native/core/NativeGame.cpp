#include "NativeGame.h"
#include "Board.hpp"
#include "CampaignState.hpp"
#include <fstream>
#include <memory>

namespace {
struct Game {
    std::unique_ptr<futari::Board> board;
    std::shared_ptr<futari::Board> title,start,stage;
    uint32_t previousRoot=0,previousPlay=0;
    int previousStage=-1;
    std::string settings,error;
};
thread_local std::string creationError;
Game &get(FutariGame g) {return *static_cast<Game*>(g);}
}
namespace futari { Board &inspectNativeGame(FutariGame game) {return *get(game).board;} }
extern "C" {
FutariGame futari_create(const char *resources,const char *settings) {
    try {
        auto g=std::make_unique<Game>();g->settings=settings;
        g->board=std::make_unique<futari::Board>(resources);
        std::ifstream in(g->settings,std::ios::binary);
        if(in) {std::array<uint8_t,512> bytes{};if(in.read((char*)bytes.data(),512))for(int i=0;i<256;i++)g->board->eeprom[i]=(bytes[i*2]<<8)|bytes[i*2+1];}
        return g.release();
    } catch(const std::exception &e){creationError=e.what();return nullptr;}
}
void futari_destroy(FutariGame game) {delete static_cast<Game*>(game);}
const char *futari_error(FutariGame game) {return game?get(game).error.c_str():creationError.c_str();}
int futari_frame(FutariGame game,uint8_t c,uint8_t d) {
    try {
        auto &g=get(game);auto &b=*g.board;b.portC=c;b.portD=d;b.frame();
        uint32_t root=b.read(0x0c38a4b4,4),play=b.read(0x0c38a578,2);
        // Scene 3 is attract/title, 5 the paid game. The inner game's transition
        // into state 4 follows completed selections and stage resource loading.
        if(root==3&&b.read(0x0c38a4bc,4)==2&&!g.title)g.title=b.checkpoint();
        int stage=int(b.read(0x0c38a586,2));
        if(root==5&&g.previousRoot!=5){g.start.reset();g.stage.reset();g.previousStage=-1;}
        if(root==5&&play==4&&stage>=0&&stage<futari::CampaignState::stageCount) {
            if(!g.start) {g.start=b.checkpoint();g.stage=g.start;}
            else if(stage!=g.previousStage)g.stage=b.checkpoint();
        }
        g.previousStage=root==5?stage:-1;
        g.previousRoot=root;g.previousPlay=play;
        return 1;
    }
    catch(const std::exception &e){get(game).error=e.what();return 0;}
}
void futari_pixels(FutariGame game,uint8_t *rgba){get(game).board->graphics.rgba(rgba);}
const float *futari_audio(FutariGame game,unsigned *count){auto &v=get(game).board->audioFrame;*count=unsigned(v.size());return v.data();}
uint64_t futari_frame_number(FutariGame game){return get(game).board->frameNumber;}
int futari_save_settings(FutariGame game) {
    auto &g=get(game);std::ofstream out(g.settings,std::ios::binary|std::ios::trunc);
    for(auto v:g.board->eeprom){out.put(v>>8);out.put(v&255);}return bool(out);
}
void futari_test_switch(FutariGame game,int enabled){get(game).board->portF=enabled?0xfd:0xff;}
int futari_restart(FutariGame game) {
    auto &g=get(game);if(!g.start)return 0;
    auto settings=g.board->eeprom;g.board=g.start->checkpoint();g.board->eeprom=settings;
    g.board->portC=g.board->portD=255;g.error.clear();g.previousRoot=5;g.previousPlay=4;
    g.previousStage=int(g.board->read(0x0c38a586,2));g.stage=g.start;return 1;
}
int futari_restart_stage(FutariGame game) {
    auto &g=get(game);if(!g.stage)return 0;
    auto settings=g.board->eeprom;g.board=g.stage->checkpoint();g.board->eeprom=settings;
    g.board->portC=g.board->portD=255;g.error.clear();g.previousRoot=5;g.previousPlay=4;
    g.previousStage=int(g.board->read(0x0c38a586,2));return 1;
}
int futari_title(FutariGame game) {
    auto &g=get(game);
    if(g.title) {
        auto settings=g.board->eeprom;g.board=g.title->checkpoint();g.board->eeprom=settings;
        g.board->portC=g.board->portD=255;g.error.clear();g.start.reset();g.stage.reset();g.previousRoot=3;g.previousPlay=0;g.previousStage=-1;return 1;
    }
    // Before the title has first appeared, request the game's own attract reset.
    if(g.board->read(0x0c38a4b4,4)>=3) {g.board->write(0x0c38a4b4,2,4);g.start.reset();g.stage.reset();return 1;}
    return 0;
}
int futari_scene(FutariGame game) {
    return int(futari::CampaignState::read(*get(game).board).phase);
}
FutariStatus futari_status(FutariGame game) {
    auto &g=get(game);auto s=futari::CampaignState::read(*g.board);
    return {int(s.phase),s.stage,futari::CampaignState::stageCount,s.mode,int(s.allClear),int(bool(g.stage))};
}
}
