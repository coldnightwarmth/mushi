#include "NativeGame.h"
#include "Board.hpp"
#include "CampaignState.hpp"
#include "NativeCustomization.hpp"
#include <fstream>
#include <memory>

namespace {
struct Game {
    std::unique_ptr<futari::Board> board;
    std::shared_ptr<futari::Board> title,start,stage;
    uint32_t previousRoot=0,previousPlay=0;
    int previousStage=-1;
    std::string settings,error;
    std::unique_ptr<futari::NativeCustomization> custom;
    std::vector<std::unique_ptr<Game>> peers;
    int initialStage=0;
};
thread_local std::string creationError;
Game &get(FutariGame g) {return *static_cast<Game*>(g);}
void clearHistory(Game &g) {if(g.custom)g.custom->history.clear();for(auto &p:g.peers)clearHistory(*p);}
int restore(Game &g,const std::shared_ptr<futari::Board> &checkpoint) {
    if(!checkpoint)return 0;
    auto settings=g.board->eeprom;g.board=checkpoint->checkpoint();g.board->eeprom=settings;
    g.board->portC=g.board->portD=g.board->portL=255;g.error.clear();
    g.previousRoot=g.board->read(0xc38a4b4,4);g.previousPlay=g.board->read(0xc38a578,2);
    g.previousStage=int(g.board->read(0xc38a586,2));
    if(g.custom){g.custom->history.clear();g.custom->presentation.clear();g.custom->formationPulse=0;}
    return 1;
}
}
namespace futari {
Board &inspectNativeGame(FutariGame game) {return *get(game).board;}
Board &inspectNativeWorld(FutariGame game,unsigned world) {auto &g=get(game);return world?*g.peers.at(world-1)->board:*g.board;}
}
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
        auto &g=get(game);
        g.board->portC=c;g.board->portD=d;
        auto before=futari::CampaignState::read(*g.board);
        if(g.custom) {
            auto &custom=*g.custom;
            if(custom.options.combined&&g.initialStage==0&&g.peers.empty()&&before.root==5&&before.play==3&&before.substate==0) {
                for(int stage=1;stage<=2;stage++) {
                    auto peer=std::make_unique<Game>();peer->board=g.board->checkpoint();peer->previousRoot=5;peer->initialStage=stage;
                    peer->custom=std::make_unique<futari::NativeCustomization>();peer->custom->options=custom.options;peer->custom->options.combined=0;peer->custom->targetStage=stage;
                    g.peers.push_back(std::move(peer));
                }
            }
            custom.begin(*g.board);
            if(custom.options.formation&&before.phase==futari::CampaignPhase::Playing) {
                if(!(g.board->read(0xc38ab74,1)&1)) {
                    // Join through the original two-player selection/continue flow.
                    g.board->write(0xc0601e4,std::max(1u,g.board->read(0xc0601e4,4)),4);
                    if(custom.formationPulse++%90<6)c&=~32;
                    g.board->portL=(custom.formationPulse%90<6)?239:255;
                } else g.board->portL=d;
            } else g.board->portL=255;
        }
        auto &b=*g.board;b.portC=c;b.portD=d;b.frame();
        if(g.custom)g.custom->end(b);
        uint32_t root=b.read(0x0c38a4b4,4),play=b.read(0x0c38a578,2);
        // Scene 3 is attract/title, 5 the paid game. The inner game's transition
        // into state 4 follows completed selections and stage resource loading.
        if(root==3&&b.read(0x0c38a4bc,4)==2&&!g.title)g.title=b.checkpoint();
        int stage=int(b.read(0x0c38a586,2));
        if(root==5&&g.previousRoot!=5){g.start.reset();g.stage.reset();g.previousStage=-1;clearHistory(g);}
        if(root==5&&play==4&&stage>=0&&stage<futari::CampaignState::stageCount) {
            if(!g.start) {g.start=b.checkpoint();g.stage=g.start;}
            else if(stage!=g.previousStage){g.stage=b.checkpoint();if(g.custom)g.custom->history.clear();}
        }
        g.previousStage=root==5?stage:-1;
        g.previousRoot=root;g.previousPlay=play;
        for(auto &peer:g.peers) {
            if(!futari_frame(peer.get(),c,d))throw std::runtime_error(peer->error);
            if(g.custom->options.combined==2&&futari::CampaignState::read(*peer->board).stage!=peer->initialStage)restore(*peer,peer->start);
        }
        if(g.custom&&g.custom->options.combined==2&&stage!=g.initialStage&&root==5&&play==4)restore(g,g.start);
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
    auto &g=get(game);if(!restore(g,g.start))return 0;g.stage=g.start;
    for(auto &p:g.peers)futari_restart(p.get());return 1;
}
int futari_restart_stage(FutariGame game) {
    auto &g=get(game);if(!restore(g,g.stage))return 0;
    for(auto &p:g.peers)futari_restart_stage(p.get());return 1;
}
int futari_title(FutariGame game) {
    auto &g=get(game);
    g.peers.clear();clearHistory(g);
    if(g.title) {
        restore(g,g.title);g.start.reset();g.stage.reset();g.previousRoot=3;g.previousPlay=0;g.previousStage=-1;return 1;
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
void futari_configure(FutariGame game,FutariCustomOptions options) {
    auto &g=get(game);if(!g.custom)g.custom=std::make_unique<futari::NativeCustomization>();
    g.custom->options=options;
    for(auto &peer:g.peers){auto local=options;local.combined=0;futari_configure(peer.get(),local);}
}
FutariStatus futari_world_status(FutariGame game,unsigned world) {
    auto &g=get(game);return futari_status(world&&world<=g.peers.size()?g.peers[world-1].get():game);
}
void futari_boost(FutariGame game,int held){auto &g=get(game);if(g.custom)g.custom->boostHeld=held!=0;for(auto &p:g.peers)futari_boost(p.get(),held);}
FutariCustomStatus futari_custom_status(FutariGame game) {
    auto &g=get(game);auto &b=*g.board;constexpr uint32_t p=0xc38aabc;unsigned count=g.custom?g.custom->history.count():0;uint64_t bytes=g.custom?g.custom->history.bytes():0;
    for(auto &peer:g.peers){auto s=futari_custom_status(peer.get());count=std::min(count,s.rewind_frames);bytes+=s.rewind_bytes;}
    return {int(b.read(0xc0601e4,4)),int(b.read(p+2,2)),int(b.read(p+6,1)),int(b.read(p+8,1)),int(b.read(p+9,1)),int32_t(b.read(p+0x38,4))/65536,320-int32_t(b.read(p+0x3c,4))/65536,int(b.read(p+0xb8,1)&1),count,unsigned(1+g.peers.size()),bytes,g.custom?g.custom->absorbed:0};
}
int futari_rewind(FutariGame game,unsigned frames) {
    auto &g=get(game);if(!g.custom)return 0;unsigned available=futari_custom_status(game).rewind_frames,n=std::min(frames,available);
    for(auto &p:g.peers)futari_rewind(p.get(),n);
    for(unsigned i=0;i<n;i++)g.custom->history.pop(g.board,g.custom->formationPulse,g.custom->absorbed);
    if(n){g.board->hooks=g.custom.get();g.board->graphics.observer=g.custom.get();g.custom->presentation.clear();g.error.clear();}
    return int(n);
}
void futari_layer_pixels(FutariGame game,unsigned world,int layer,int width,int height,uint8_t *rgba) {
    auto &g=get(game);if(world&&world<=g.peers.size()){futari_layer_pixels(g.peers[world-1].get(),0,layer,width,height,rgba);return;}
    if(futari_presentation_ready(game))g.custom->presentation.rgba(layer,width,height,rgba,g.board->graphics.scrollX,g.board->graphics.scrollY);
    else if(layer==0) {
        width=std::clamp(width,1,304);height=std::clamp(height,1,384);auto &v=g.board->graphics;
        for(int y=0;y<height;y++)for(int x=0;x<width;x++) {
            auto p=v.pixels[((int(v.scrollY)+x-(width-240)/2)&4095)*8192+((int(v.scrollX)+319-y+(height-320)/2)&8191)];
            auto i=(y*width+x)*4;rgba[i]=(p>>16)&248;rgba[i+1]=(p>>8)&248;rgba[i+2]=p&248;rgba[i+3]=255;
        }
    }
    else std::fill(rgba,rgba+std::clamp(width,1,304)*std::clamp(height,1,384)*4,0);
}
int futari_presentation_ready(FutariGame game) {
    auto &g=get(game);return g.custom&&g.custom->presentation.displayDraws&&!g.custom->presentation.displayDraws->empty();
}
}
