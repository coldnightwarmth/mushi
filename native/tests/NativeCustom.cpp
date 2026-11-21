#include "NativeInspection.hpp"
#include "CampaignState.hpp"
#include "NativeCustomization.hpp"
#include <fstream>
#include <map>
#include <cmath>
#include <cstring>
#include <chrono>
#include <cstdio>
static void check(bool b,const char *m){if(!b)throw std::runtime_error(m);}
int main(int argc,char**argv){
 if(argc<4){puts("NativeCustom resources menu-inputs.tsv output-prefix [combined|endless|campaign]");return 2;}
 std::string prefix=argv[3];auto game=futari_create(argv[1],(prefix+".settings").c_str());
 try {
  check(game,"create");std::ifstream in(argv[2]);std::map<unsigned,std::pair<unsigned,unsigned>> inputs;unsigned f,c,d;while(in>>f>>c>>d)inputs[f]={c,d};c=d=255;
  std::string mode=argc>4?argv[4]:"standard";
  FutariCustomOptions options{};options.rewind_enabled=1;
  if(mode!="standard"){options.combined=mode=="endless"?2:mode=="combined"?1:0;options.protection=1;options.formation=1;options.infinite_credits=1;options.infinite_bombs=1;futari_configure(game,options);}
  auto step=[&](unsigned C,unsigned D){check(futari_frame(game,C,D),futari_error(game));};
  for(f=0;f<4000;f++){if(inputs.count(f)){c=inputs[f].first;d=inputs[f].second;}step(c,d);}
  if(mode=="campaign") {
   std::array<bool,5> stages{};options.rewind_enabled=0;futari_configure(game,options);
   for(unsigned i=0;i<130000;i++) {
    step(255,(i%240<12)?159:191);auto status=futari_status(game);
    if(status.phase==3) {
     check(status.stage>=0&&status.stage<5,"stage range");
     if(!stages[status.stage]){stages[status.stage]=true;printf("campaign stage %d frame %llu\n",status.stage+1,futari_frame_number(game));fflush(stdout);}
     if(i%120==0){std::vector<uint8_t> raw(240*320*4),layer(raw.size());futari_pixels(game,raw.data());futari_layer_pixels(game,0,0,240,320,layer.data());if(raw!=layer){std::ofstream(prefix+"-mismatch-native.rgba",std::ios::binary).write((char*)raw.data(),raw.size());std::ofstream(prefix+"-mismatch-layer.rgba",std::ios::binary).write((char*)layer.data(),layer.size());fprintf(stderr,"composition mismatch at frame %llu\n",futari_frame_number(game));}check(raw==layer,"campaign original/layer composition");}
    }
    if(status.all_clear){for(bool seen:stages)check(seen,"all five custom stages visited");printf("PASS custom five-stage campaign, formation, protection, bombs and layered graphics\n");futari_destroy(game);return 0;}
   }
   throw std::runtime_error("custom campaign did not clear");
  }
  if(mode=="combined"||mode=="endless") {
   for(unsigned i=0;i<400;i++)step(255,191);auto s=futari_custom_status(game);check(s.worlds==3,"three native worlds");check(s.wing_active,"Reco/Palm formation");
   check(s.rewind_bytes<=3ull*192*1024*1024,"combined rewind allocation budget");
   std::array<std::unique_ptr<futari::Board>,3> reference;
   for(unsigned world=0;world<3;world++) {
    check(futari_world_status(game,world).stage==int(world),"combined stages 1/2/3");
    std::vector<uint8_t> rgba(240*320*4);futari_layer_pixels(game,world,0,240,320,rgba.data());std::ofstream(prefix+"-world-"+std::to_string(world)+".rgba",std::ios::binary).write((char*)rgba.data(),rgba.size());
    reference[world]=futari::inspectNativeWorld(game,world).checkpoint();
   }
   check(futari_rewind(game,30)==30,"combined rewind");for(unsigned i=0;i<30;i++)step(255,191);
   for(unsigned world=0;world<3;world++){auto &b=futari::inspectNativeWorld(game,world);check(b.ram==reference[world]->ram&&b.graphics.pixels==reference[world]->graphics.pixels&&b.audioFrame==reference[world]->audioFrame,"combined exact reverse/replay");reference[world].reset();}
   printf("PASS combined three stages, formation and exact 30-frame rewind/replay\n");fflush(stdout);
   if(mode=="endless") {
    options.rewind_enabled=0;futari_configure(game,options);std::array<bool,3> looped{};std::array<uint64_t,3> frames{};
    for(unsigned i=0;i<30000;i++) {
     for(unsigned world=0;world<3;world++)frames[world]=futari::inspectNativeWorld(game,world).frameNumber;
     step(255,(i%240<12)?159:191);
     for(unsigned world=0;world<3;world++) {
      if(futari::inspectNativeWorld(game,world).frameNumber<frames[world]) {looped[world]=true;check(futari_world_status(game,world).stage==int(world),"independent endless opening");printf("world %u looped at test tick %u\n",world,i);fflush(stdout);}
     }
     if(looped[0]&&looped[1]&&looped[2]){puts("PASS all three endless worlds loop independently");futari_destroy(game);return 0;}
    }
    throw std::runtime_error("endless worlds did not all loop");
   }
   futari_destroy(game);return 0;
  }
  auto &first=futari::inspectNativeGame(game);auto baseline=first.checkpoint();
  futari_configure(game,options);auto start=std::chrono::steady_clock::now();
  for(unsigned i=0;i<60;i++) {
   unsigned input=~(0x40u|(i<30?4u:i<60?8u:0u))&255;step(255,input);baseline->portC=255;baseline->portD=input;baseline->frame();
   auto &b=futari::inspectNativeGame(game);check(b.ram==baseline->ram,"custom off changed game RAM");check(b.audioFrame==baseline->audioFrame,"custom off changed audio");
  }
  auto &b=futari::inspectNativeGame(game);check(b.graphics.pixels==baseline->graphics.pixels,"custom off changed VRAM");
  std::vector<uint8_t> native(240*320*4),layer(native.size());futari_pixels(game,native.data());futari_layer_pixels(game,0,0,240,320,layer.data());
  size_t different=0;for(size_t i=0;i<native.size();i++)if(native[i]!=layer[i])++different;
  printf("layer differences=%zu\n",different);check(different==0,"native layered composition");
  std::ofstream(prefix+"-layer-0.rgba",std::ios::binary).write((char*)layer.data(),layer.size());
  std::ofstream(prefix+"-native.rgba",std::ios::binary).write((char*)native.data(),native.size());
  for(int k=1;k<5;k++){futari_layer_pixels(game,0,k,240,320,layer.data());std::ofstream(prefix+"-layer-"+std::to_string(k)+".rgba",std::ios::binary).write((char*)layer.data(),layer.size());}
  std::vector<uint8_t> composite(native.size()),overlay(native.size());futari_layer_pixels(game,0,1,240,320,composite.data());
  for(int kind:{2,3}) {futari_layer_pixels(game,0,kind,240,320,overlay.data());for(size_t i=0;i<native.size();i+=4)if(overlay[i+3])std::copy_n(overlay.data()+i,4,composite.data()+i);}
  check(composite==native,"scenery, actors and HUD recombine exactly");
  check(futari_custom_status(game).rewind_bytes<=192ull*1024*1024,"rewind allocation budget");
  auto reference=b.checkpoint();check(futari_rewind(game,60)==60,"60 reverse frames");
  for(unsigned i=0;i<60;i++)step(255,~(0x40u|(i<30?4u:i<60?8u:0u))&255);
  auto &replayed=futari::inspectNativeGame(game);check(replayed.ram==reference->ram,"rewind RAM diverged");check(replayed.graphics.pixels==reference->graphics.pixels,"rewind VRAM diverged");check(replayed.audioFrame==reference->audioFrame,"rewind audio diverged");
  printf("PASS baseline equivalence and exact 60-frame reverse/replay (%.3fs)\n",std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());fflush(stdout);
  options.protection=1;futari_configure(game,options);
  int x0=futari_custom_status(game).player_x;
  for(unsigned i=0;i<5;i++)step(255,247);
  int ordinary=futari_custom_status(game).player_x-x0;check(futari_rewind(game,5)==5,"boost setup rewind");
  options.boost=1;futari_configure(game,options);futari_boost(game,1);
  for(unsigned i=0;i<5;i++)step(255,247);
  int boosted=futari_custom_status(game).player_x-x0;check(std::abs(boosted*2-ordinary*5)<=3&&boosted>ordinary,"2.5x boost distance");
  futari_boost(game,0);options.rewind_enabled=0;futari_configure(game,options);
  for(unsigned i=0;i<120;i++)step(255,251);
  check(futari_custom_status(game).player_x==8,"original left boundary");
  options.horizontal=2;futari_configure(game,options);
  for(unsigned i=0;i<120;i++)step(255,251);
  check(futari_custom_status(game).player_x==-24,"open left boundary");
  for(unsigned i=0;i<180;i++)step(255,247);
  check(futari_custom_status(game).player_x==264,"open right boundary");
  options.horizontal=0;futari_configure(game,options);
  for(unsigned i=0;i<40;i++)step(255,251);
  printf("PASS Shift boost and original/open horizontal movement limits\n");fflush(stdout);
  options.rewind_enabled=0;options.protection=1;options.infinite_credits=1;options.infinite_bombs=1;options.formation=1;futari_configure(game,options);
  auto lives=futari_custom_status(game).lives;
  for(unsigned i=0;i<2000;i++)step(255,191);
  auto s=futari_custom_status(game);check(s.credits==9&&s.bombs==3,"infinite resources");check(s.lives>=lives,"invincibility");check(s.wing_active,"formation join");
  check(futari::inspectNativeGame(game).read(0xc38ab7c,1)!=unsigned(s.character),"formation contains both characters");
  printf("PASS native resources, invincibility and Reco/Palm formation\n");fflush(stdout);
  options.exploration=1;futari_configure(game,options);auto &w=futari::inspectNativeGame(game);auto clock=w.read(0xc38a59c,4),camera=w.read(0xc51eb48,4);
  for(unsigned i=0;i<90;i++)step(255,191);
  check(futari::inspectNativeGame(game).read(0xc38a59c,4)==clock,"exploration clock freeze");check(futari::inspectNativeGame(game).read(0xc51eb48,4)==camera,"exploration scenery freeze");
  for(unsigned i=0;i<30;i++)step(255,190);
  check(futari::inspectNativeGame(game).read(0xc38a59c,4)>clock,"exploration advance");
  auto moved=futari::inspectNativeGame(game).read(0xc51eb48,4);check(moved!=camera,"exploration scenery advances");
  for(unsigned i=0;i<30;i++)step(255,189);
  auto returned=futari::inspectNativeGame(game).read(0xc51eb48,4);check(std::abs(int32_t(returned-camera))<std::abs(int32_t(moved-camera)),"exploration scenery reverses");
  printf("PASS exploration stop, forward and reverse scenery\n");fflush(stdout);
  options.exploration=0;options.protection=3;options.infinite_bombs=0;futari_configure(game,options);
  futari::inspectNativeGame(game).write(0xc38aac2,0,1);
  for(unsigned i=0;i<3000;i++)step(255,255);
  s=futari_custom_status(game);printf("absorption contacts=%llu\n",s.absorbed);check(s.absorbed>0&&s.bombs==3,"absorption contact refills bombs");
  printf("PASS absorbing contacts refill bombs\n");
  options.protection=2;futari_configure(game,options);futari::inspectNativeGame(game).write(0xc38aabe,1,2);step(255,255);
  check(futari_custom_status(game).lives==9,"infinite lives replenishes bank");
  printf("PASS infinite respawns\n");
  futari_destroy(game);return 0;
 }catch(const std::exception &e){fprintf(stderr,"FAIL %s\n",e.what());if(game)futari_destroy(game);return 1;}
}
