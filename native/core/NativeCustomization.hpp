#pragma once
#include "NativeGame.h"
#include "CampaignState.hpp"
#include "NativeHistory.hpp"
#include "NativePresentation.hpp"
namespace futari {
struct NativeCustomization final:BoardHooks,GraphicsObserver {
 FutariCustomOptions options{};NativePresentation presentation;NativeHistory history;
 bool boostHeld=false,recording=false;int targetStage=-1,travel=0;unsigned formationPulse=0;uint64_t absorbed=0;
 static constexpr uint32_t player=0xc38aabc,context=0xc38a530;
 void writing(Board &b,uint32_t a,uint32_t &v,unsigned size)override {
  if(recording)history.beforeRAMWrite(b,a,size);
  presentation.tag(b,a,v,size);
  if(targetStage>=0&&a==context+0x54&&CampaignState::read(b).play==3)v=targetStage;
  if(options.exploration&&CampaignState::read(b).phase==CampaignPhase::Playing) {
   if(a==context+0x6c&&b.state.pc==0xc06c2c0)v=b.read(a,size)+unsigned(std::max(0,travel));
   if(b.state.pc==0xc09b95a&&a>=0xc51e948&&a<0xc51ec68) {
    int64_t old=int32_t(b.read(a,size)),delta=int32_t(v)-old;
    v=uint32_t(std::max<int64_t>(0,old+delta*travel));
   }
  }
 }
 bool native(Board &b,uint32_t pc,CompiledState &s)override {
  if(CampaignState::read(b).phase!=CampaignPhase::Playing)return false;
  if(pc==0xc07900e&&options.boost&&boostHeld) {
   uint32_t body=s.r[10];
   for(unsigned off:{12u,16u})b.write(body+off,uint32_t(int64_t(int32_t(b.read(body+off,4)))*5/2),4);
  }
  if(options.horizontal==2) {
   if(pc==0xc07902a)s.r[1]=uint32_t(-24*65536);
   if(pc==0xc079036)s.r[1]=264*65536-1;
   // The scrolling controller applies a second clamp when movement reaches
   // the edge. Its limits must agree with the player's movement routine.
   if(pc==0xc09c712)s.r[1]=uint32_t(-24*65536);
   if(pc==0xc09c6fe)s.r[3]=264*65536-1;
   if(pc==0xc09c706)s.r[5]=264*65536;
  }
  if(pc==0xc079e86&&options.protection==3&&s.r[0]&&(b.read(s.r[8],4)&0xc18)) {
   uint32_t p=b.read(s.r[12]+0x10,4);
   if(p==player||p==player+0xb8){b.write(p+6,std::min(3u,b.read(p+6,1)+1),1);++absorbed;}
  }
  if(pc==0xc09b912&&options.exploration) {
   for(unsigned off:{0x1cu,0x20u})b.write(s.r[8]+off,uint32_t(int64_t(int32_t(b.read(s.r[8]+off,4)))*travel),4);
  }
  return false;
 }
 void written(int,int,int,int)override{}
 void draw(const Graphics&,uint32_t,uint16_t,int,int,int,int)override{}
 void beforeWrite(const Graphics &g,int x,int y,int w,int h)override {if(recording)history.beforeWrite(g,x,y,w,h);}
 void blit(const Graphics &g,uint32_t a,uint16_t attr,uint16_t alpha,int sx,int sy,int dx,int dy,int w,int h,int x0,int y0,int x1,int y1,uint32_t tint)override {
  presentation.capture(g,a,attr,alpha,sx,sy,dx,dy,w,h,x0,y0,x1,y1,tint);
 }
 void resources(Board &b) {
  if(options.infinite_credits)b.write(0xc0601e4,9,4);
  if(CampaignState::read(b).phase!=CampaignPhase::Playing)return;
  for(unsigned p:{player,player+0xb8})if(b.read(p,1)&1) {
   if(options.infinite_bombs)b.write(p+6,3,1);
   if(options.protection==2)b.write(p+2,9,2);
   if(options.protection==1||options.protection==3)b.write(p+0x68,std::max(2u,b.read(p+0x68,4)),4);
  }
 }
 void begin(Board &b) {
  presentation.randomTrails=options.random_trails;presentation.begin(b.frameNumber);b.hooks=this;b.graphics.observer=this;
  recording=options.rewind_enabled&&CampaignState::read(b).phase==CampaignPhase::Playing;
  if(recording)history.begin(b,formationPulse,absorbed);resources(b);
  travel=(b.portD&1)?((b.portD&2)?0:-4):4;
 }
 void end(Board &b) {resources(b);if(recording)history.finish();recording=false;presentation.complete(b.graphics.scrollX,b.graphics.scrollY);}
};
}
