#include "NativeGame.h"
#include <fstream>
#include <map>
#include <vector>
#include <cstdio>
#include <stdexcept>
#include <cstring>
#include <iterator>

int main(int argc,char **argv) {
    if(argc!=4)return 2;
    FutariGame game=futari_create(argv[1],argv[3]);
    if(!game){fprintf(stderr,"%s\n",futari_error(nullptr));return 1;}
    try {
        auto frame=[&](unsigned c,unsigned d){if(!futari_frame(game,c,d))throw std::runtime_error(futari_error(game));};
        std::map<unsigned,std::pair<unsigned,unsigned>> events;
        std::ifstream replay(argv[2]);unsigned f,c=255,d=255;
        while(replay>>f>>c>>d)events[f]={c,d};c=d=255;
        for(f=0;f<3500;f++){auto e=events.find(f);if(e!=events.end()){c=e->second.first;d=e->second.second;}frame(c,d);}
        auto repeat=[&]() {
            if(!futari_restart(game))throw std::runtime_error("No stage restart checkpoint");
            std::vector<uint8_t> result;
            for(unsigned tick=0;tick<90;tick++) {
                frame(255,uint8_t(~(0x10|(tick<30?4:tick<60?8:0))));
                std::vector<uint8_t> pixels(240*320*4);futari_pixels(game,pixels.data());
                result.insert(result.end(),pixels.begin(),pixels.end());
                unsigned count=0;auto audio=futari_audio(game,&count);
                auto bytes=reinterpret_cast<const uint8_t*>(audio);
                result.insert(result.end(),bytes,bytes+count*sizeof(float));
            }
            return result;
        };
        auto first=repeat(),second=repeat();
        if(first!=second)throw std::runtime_error("Restart diverged in pixels or audio");
        if(!futari_title(game))throw std::runtime_error("Title transition failed");
        for(int i=0;i<360;i++)frame(255,255);
        // Enter the original operator menu through the board's test switch.
        futari_test_switch(game,1);for(int i=0;i<180;i++)frame(255,255);futari_test_switch(game,0);
        for(int i=0;i<900;i++)frame(255,255);
        if(futari_scene(game)!=4)throw std::runtime_error("Operator menu did not open");
        std::vector<uint8_t> pixels(240*320*4);futari_pixels(game,pixels.data());
        std::ofstream(std::string(argv[3])+".operator.rgba",std::ios::binary).write((char*)pixels.data(),pixels.size());
        for(int row=0;row<6;row++){for(int i=0;i<3;i++)frame(255,0xfd);for(int i=0;i<12;i++)frame(255,255);}
        for(int i=0;i<3;i++)frame(255,0xef);for(int i=0;i<120;i++)frame(255,255);
        futari_pixels(game,pixels.data());
        std::ofstream(std::string(argv[3])+".settings.rgba",std::ios::binary).write((char*)pixels.data(),pixels.size());
        if(!futari_save_settings(game))throw std::runtime_error("Initial settings save failed");
        auto readSettings=[&]() {
            std::ifstream in(argv[3],std::ios::binary);
            return std::vector<uint8_t>(std::istreambuf_iterator<char>(in),{});
        };
        auto beforeSettings=readSettings();
        auto tap=[&](uint8_t d) {for(int i=0;i<3;i++)frame(255,d);for(int i=0;i<15;i++)frame(255,255);};
        // Change difficulty, leave GAME, then leave TEST MENU through its Exit.
        tap(0xf7);
        futari_pixels(game,pixels.data());
        auto changedPixels=pixels;
        std::ofstream(std::string(argv[3])+".changed.rgba",std::ios::binary).write((char*)pixels.data(),pixels.size());
        for(int row=0;row<3;row++)tap(0xfd);tap(0xef);
        for(int i=0;i<120;i++)frame(255,255);
        futari_pixels(game,pixels.data());
        std::ofstream(std::string(argv[3])+".settings-exit.rgba",std::ios::binary).write((char*)pixels.data(),pixels.size());
        for(int row=0;row<4;row++)tap(0xfd);tap(0xef);
        for(int i=0;i<120;i++)frame(255,255);
        // TEST MENU's Exit opens a separate SAVE & EXIT confirmation.
        tap(0xef);for(int i=0;i<600;i++)frame(255,255);
        futari_pixels(game,pixels.data());
        std::ofstream(std::string(argv[3])+".operator-exit.rgba",std::ios::binary).write((char*)pixels.data(),pixels.size());
        if(futari_scene(game)==4)throw std::runtime_error("Operator Exit did not return to game");
        if(!futari_save_settings(game))throw std::runtime_error("Settings save failed");
        auto afterSettings=readSettings();
        if(beforeSettings==afterSettings)throw std::runtime_error("Changed operator setting was not persisted");
        futari_destroy(game);game=nullptr;
        std::ifstream settings(argv[3],std::ios::binary|std::ios::ate);
        if(settings.tellg()!=512)throw std::runtime_error("Settings file has wrong size");
        game=futari_create(argv[1],argv[3]);
        if(!game)throw std::runtime_error(futari_error(nullptr));
        if(!futari_save_settings(game)||readSettings()!=afterSettings)throw std::runtime_error("Settings did not survive app recreation");
        for(int i=0;i<2400;i++)frame(255,255);
        futari_test_switch(game,1);for(int i=0;i<180;i++)frame(255,255);futari_test_switch(game,0);
        for(int i=0;i<900;i++)frame(255,255);
        for(int row=0;row<6;row++)tap(0xfd);tap(0xef);
        for(int i=0;i<120;i++)frame(255,255);
        futari_pixels(game,pixels.data());
        std::ofstream(std::string(argv[3])+".reloaded.rgba",std::ios::binary).write((char*)pixels.data(),pixels.size());
        for(unsigned y=70;y<82;y++)for(unsigned x=70;x<200;x++)for(unsigned k=0;k<4;k++)
            if(pixels[(y*240+x)*4+k]!=changedPixels[(y*240+x)*4+k])throw std::runtime_error("Reloaded difficulty display differs from saved setting");
        futari_destroy(game);game=nullptr;
        puts("Native host: menus to stage, 90-frame restart pixels/audio exact, title, operator configuration/exit, changed settings persisted across recreation");
        return 0;
    } catch(const std::exception &e) {fprintf(stderr,"%s\n",e.what());if(game)futari_destroy(game);return 1;}
}
