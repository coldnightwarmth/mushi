#include "Graphics.hpp"
#include <array>

namespace futari {
static int weight(int mode,int alpha,int source,int destination) {
    switch(mode) {
    case 0:return alpha;case 1:return source;case 2:return destination;
    case 4:return 31-alpha;case 5:return 31-source;case 6:return 31-destination;
    default:return 31;
    }
}
void Graphics::execute(Bus &bus) {
    uint32_t address=list; bool clip=true; ++lists;
    auto word=[&](){uint16_t v=bus.read(address,2);address+=2;return v;};
    for(unsigned commands=0;commands<100000;commands++) {
        uint32_t commandAddress=address;
        uint16_t attr=word();unsigned op=attr>>12;
        if(op==0||op==15) return;
        if(op==12) {clip=word()!=0;continue;}
        if(op!=1&&op!=2) throw std::runtime_error("Invalid graphics command");
        uint16_t alpha=word();int sx=word()&8191,sy=word()&4095;
        int dx=int16_t(word()),dy=int16_t(word());
        int width=(word()&8191)+1,height=(word()&4095)+1;
        if(op==2) {
            ++uploads;dx&=8191;dy&=4095;
            if(observer)observer->beforeWrite(*this,dx,dy,width,height);
            for(int y=0;y<height;y++) for(int x=0;x<width;x++) {
                uint16_t p=word();
                pixels[((dy+y)&4095)*8192+((dx+x)&8191)]=((p&0x8000u)<<14)|((p&0x7c00u)<<9)|((p&0x3e0u)<<6)|((p&31u)<<3);
            }
            if(observer)observer->written(dx,dy,width,height);
            continue;
        }
        ++draws;
        unsigned tintR=(word()&255)>>2,tintGB=word();
        if(observer)observer->draw(*this,commandAddress,attr,sx,sy,width,height);
        int tint[3]={int(tintR),int((tintGB>>10)&63),int((tintGB>>2)&63)};
        bool tinted=tint[0]!=32||tint[1]!=32||tint[2]!=32;
        bool transparent=attr&0x100,blend=attr&0x200,flipY=attr&0x400,flipX=attr&0x800;
        int sa=alpha>>11,da=(alpha&255)>>3,sm=(attr>>4)&7,dm=attr&7;
        if(sm==0&&dm==4&&sa==31&&da==31) blend=false;
        if(sx+width>8192) continue;
        int x0=std::max(0,(clip?std::max(0,int(clipX)-32):0)-dx);
        int y0=std::max(0,(clip?std::max(0,int(clipY)-32):0)-dy);
        int x1=std::min(width,(clip?std::min(8192,int(clipX)+352):8192)-dx);
        int y1=std::min(height,(clip?std::min(4096,int(clipY)+272):4096)-dy);
        if(observer&&x1>x0&&y1>y0) {
            observer->blit(*this,commandAddress,attr,alpha,sx,sy,dx,dy,width,height,x0,y0,x1,y1,(tintR<<16)|tintGB);
            observer->beforeWrite(*this,dx+x0,dy+y0,x1-x0,y1-y0);
        }
        for(int y=y0;y<y1;y++) {
            unsigned sourceRow=((sy+(flipY?height-1-y:y))&4095)*8192;
            auto *dst=pixels.data()+(dy+y)*8192;
            for(int x=x0;x<x1;x++) {
                uint32_t source=pixels[sourceRow+sx+(flipX?width-1-x:x)];
                if(transparent&&!(source&0x20000000)) continue;
                if(!blend&&!tinted) {dst[dx+x]=source;continue;}
                int s[3]={int((source>>19)&31),int((source>>11)&31),int((source>>3)&31)};
                if(tinted) for(int k=0;k<3;k++) s[k]=std::min(31,s[k]*tint[k]/31);
                if(blend) {
                    uint32_t dest=dst[dx+x];int d[3]={int((dest>>19)&31),int((dest>>11)&31),int((dest>>3)&31)};
                    int a[3],b[3];
                    for(int k=0;k<3;k++) {a[k]=s[k]*weight(sm,sa,s[k],d[k])/31;b[k]=d[k]*weight(dm,da,s[k],d[k])/31;}
                    // Preserve the reference's destination-square channel behavior.
                    for(int k=0;k<3;k++) s[k]=std::min(31,a[dm==2?0:k]+b[k]);
                }
                dst[dx+x]=(source&0x20000000)|(s[0]<<19)|(s[1]<<11)|(s[2]<<3);
            }
        }
        if(observer&&x1>x0&&y1>y0)observer->written(dx+x0,dy+y0,x1-x0,y1-y0);
    }
    throw std::runtime_error("Unterminated graphics list");
}
void Graphics::rgba(uint8_t *output) const {
    for(int y=0;y<320;y++) for(int x=0;x<240;x++) {
        uint32_t p=pixels[((scrollY+x)&4095)*8192+((scrollX+319-y)&8191)];
        size_t i=(y*240+x)*4;
        output[i]=(p>>16)&248;output[i+1]=(p>>8)&248;output[i+2]=p&248;output[i+3]=255;
    }
}
}
