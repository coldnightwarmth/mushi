#include "NativePresentation.hpp"
namespace futari {
static int weight(int mode,int alpha,int source,int dest) {
 switch(mode){case 0:return alpha;case 1:return source;case 2:return dest;case 4:return 31-alpha;case 5:return 31-source;case 6:return 31-dest;default:return 31;}
}
static uint32_t blend(uint32_t source,uint32_t dest,uint16_t attr,uint16_t alpha,uint32_t tint) {
 int s[3]={int(source>>19&31),int(source>>11&31),int(source>>3&31)};
 int t[3]={int(tint>>16),int(tint>>10&63),int(tint>>2&63)};
 bool tinted=t[0]!=32||t[1]!=32||t[2]!=32;
 if(tinted)for(int k=0;k<3;k++)s[k]=std::min(31,s[k]*t[k]/31);
 int sm=(attr>>4)&7,dm=attr&7,sa=alpha>>11,da=(alpha&255)>>3;
 if((attr&0x200)&&!(sm==0&&dm==4&&sa==31&&da==31)) {
  int d[3]={int(dest>>19&31),int(dest>>11&31),int(dest>>3&31)},a[3],b[3];
  for(int k=0;k<3;k++){a[k]=s[k]*weight(sm,sa,s[k],d[k])/31;b[k]=d[k]*weight(dm,da,s[k],d[k])/31;}
  for(int k=0;k<3;k++)s[k]=std::min(31,a[dm==2?0:k]+b[k]);
 }
 return 0x20000000|(s[0]<<19)|(s[1]<<11)|(s[2]<<3);
}
void NativePresentation::tag(Board &b,uint32_t address,uint32_t value,unsigned size) {
 // The native renderer submits 20-byte commands in the two command buffers.
 // Its sorted draw queue stores the next priority bucket on the saved stack.
 if(address<0xc530000||address>=0xc640000||size!=4||(value>>28)!=1)return;
 if(b.state.pc<0xc051000||b.state.pc>=0xc060000)return;
 Tag tag;
 for(unsigned off=0;off<128;off+=4) {
  auto p=b.read(b.state.r[15]+off,4);
  if(p>=0xc058348&&p<=0xc059340&&(p&7)==0){tag.priority=int((p-0xc058340)/8)-1;break;}
 }
 tag.scenery=b.state.pr==0xc09c7aa;
 tag.callback=b.state.pr;
 tags[address]=tag;
 if(tags.size()>30000)tags.clear();
}
void NativePresentation::capture(const Graphics &g,uint32_t address,uint16_t attr,uint16_t alpha,int sx,int sy,int dx,int dy,int w,int h,int x0,int y0,int x1,int y1,uint32_t tint) {
 int originX=int(g.clipX),originY=int(g.clipY);
 x0=std::max(x0,originX-32-dx);x1=std::min(x1,originX+352-dx);
 y0=std::max(y0,originY-32-dy);y1=std::min(y1,originY+272-dy);
 if(x0>=x1||y0>=y1)return;
 if((this->originX!=originX||this->originY!=originY)&&!draws.empty())buffers[{this->originX,this->originY}]=std::make_shared<std::vector<Draw>>(std::move(draws));
 this->originX=originX;this->originY=originY;
 auto found=tags.find(address&0x1fffffff);Tag tag=found==tags.end()?Tag{}:found->second;
 int layer=(tag.scenery||tag.priority==119)?1:(tag.priority>=236?3:2);
 Draw d{dx+x0-originX+32,dy+y0-originY+32,x1-x0,y1-y0,layer,attr,alpha,tint,{}};
 d.priority=tag.priority;
 d.source.reserve(d.w*d.h);
 for(int y=y0;y<y1;y++)for(int x=x0;x<x1;x++)d.source.push_back(g.pixels[((sy+((attr&0x400)?h-1-y:y))&4095)*8192+sx+((attr&0x800)?w-1-x:x)]);
 // Burst effects occupy the original high actor priorities; gameplay masks use
 // all actor draws, while the effect plane supplies blossoms and sediment.
 if(layer==2&&tag.priority>=150&&tag.priority<154)d.layer=4;
 // Match observed variants by original draw callback, priority, atlas page and
 // clipped geometry. The game RNG and animation records are never changed.
 d.family=(uint64_t(tag.callback)<<32)^uint64_t((tag.priority+1)*131+(sx/256)*17+sy/256);
 d.family=d.family*1099511628211ull^uint64_t(d.w*512+d.h);
 if(layer==2&&randomTrails) {
  uint64_t hash=1469598103934665603ull;
  for(auto p:d.source)hash=(hash^p)*1099511628211ull;
  if(variantBytes>16*1024*1024){variants.clear();variantBytes=0;}
  auto &family=variants[d.family];
  if(std::none_of(family.begin(),family.end(),[&](auto &v){return v.hash==hash;})) {
   if(family.size()==8){variantBytes-=family.front().pixels.size()*4;family.erase(family.begin());}
   family.push_back({hash,d.source});variantBytes+=d.source.size()*4;
  }
 }
 draws.push_back(std::move(d));
}
void NativePresentation::complete(int scrollX,int scrollY) {
 if(!draws.empty())buffers[{originX,originY}]=std::make_shared<std::vector<Draw>>(std::move(draws));
 displayDraws.reset();int nearest=65;
 for(auto &buffer:buffers) {
  int distance=std::abs(scrollX-buffer.first.first)+std::abs(scrollY-buffer.first.second);
  if(distance<nearest){nearest=distance;displayDraws=buffer.second;displayOriginX=buffer.first.first;displayOriginY=buffer.first.second;}
 }
 // Normal play has two surfaces; discard obsolete surfaces across transitions.
 if(buffers.size()>4){auto selected=displayDraws;buffers.clear();if(selected)buffers[{displayOriginX,displayOriginY}]=selected;}
 ready=false;
}
void NativePresentation::finish() {
 if(ready)return;ready=true;
 for(auto &p:planes)p.assign(384*304,0);
 if(!displayDraws)return;
 for(const auto &d:*displayDraws)for(int y=0;y<d.h;y++)for(int x=0;x<d.w;x++) {
  uint32_t s=d.source[y*d.w+x];if((d.attr&0x100)&&!(s&0x20000000))continue;
  unsigned i=(d.y+y)*384+d.x+x;
  auto prior=planes[0][i],color=blend(s,prior,d.attr,d.alpha,d.tint);
  planes[0][i]=color;
  if(d.layer==1) {
   planes[1][i]=blend(s,planes[1][i],d.attr,d.alpha,d.tint);
   bool translucent=(d.attr&0x200)&&!(((d.attr>>4)&7)==0&&(d.attr&7)==4&&(d.alpha>>11)==31&&((d.alpha&255)>>3)==31);
   if(translucent){if(planes[2][i])planes[2][i]=color;if(planes[4][i])planes[4][i]=color;}
   else planes[2][i]=planes[4][i]=0;
  }
  else if(color!=prior) {
   if(d.layer==3)planes[3][i]=color;
   else {planes[2][i]=color;if(d.layer==4)planes[4][i]=color;}
  }
 }
 // A separate actors-only plane supplies Random afterimages. Every replacement
 // is an actual source rectangle already observed from the matching family.
 for(const auto &d:*displayDraws)if(randomTrails&&(d.layer==2||d.layer==4)) {
  auto family=variants.find(d.family);const auto *source=&d.source;
  if(family!=variants.end()&&!family->second.empty()) {
   auto seed=(d.family^(tick*0x9e3779b97f4a7c15ull)^uint64_t(d.x*307+d.y))*0xbf58476d1ce4e5b9ull;
   source=&family->second[(seed^(seed>>31))%family->second.size()].pixels;
  }
  for(int y=0;y<d.h;y++)for(int x=0;x<d.w;x++) {
   auto s=(*source)[y*d.w+x];if((d.attr&0x100)&&!(s&0x20000000))continue;
   auto i=(d.y+y)*384+d.x+x;auto color=blend(s,planes[1][i],d.attr,d.alpha,d.tint);
   if(color!=planes[1][i])planes[5][i]=color;
  }
 }
}
void NativePresentation::rgba(int layer,int width,int height,uint8_t *out,int scrollX,int scrollY) {
 finish();layer=std::clamp(layer,0,5);width=std::clamp(width,1,304);height=std::clamp(height,1,384);
 for(int y=0;y<height;y++)for(int x=0;x<width;x++) {
  int px=383-y-(384-height)/2+(scrollX<0?0:scrollX-displayOriginX),py=x+(304-width)/2+(scrollY<0?0:scrollY-displayOriginY);
  uint32_t p=px>=0&&px<384&&py>=0&&py<304?planes[layer][py*384+px]:0;unsigned i=(y*width+x)*4;
  out[i]=(p>>16)&248;out[i+1]=(p>>8)&248;out[i+2]=p&248;out[i+3]=(layer==0||layer==1||(p&0x20000000))?255:0;
 }
}
}
