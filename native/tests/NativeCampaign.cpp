#include "NativeInspection.hpp"
#include "CampaignState.hpp"
#include "NativeAssets.hpp"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <map>

static std::string hexDigest(const unsigned char *bytes,unsigned count) {
    static const char digits[]="0123456789abcdef";std::string s;
    for(unsigned i=0;i<count;i++){s+=digits[bytes[i]>>4];s+=digits[bytes[i]&15];}return s;
}
int main(int argc,char **argv) {
    if(argc!=5){fprintf(stderr,"NativeCampaign resources menu-replay.tsv output-prefix resource-hashes.tsv\n");return 2;}
    std::string prefix=argv[3];FutariGame game=nullptr;
    try {
        NativeAssets assets(argv[4]);
        game=futari_create(argv[1],(prefix+".settings.bin").c_str());
        if(!game)throw std::runtime_error(futari_error(nullptr));
        std::map<unsigned,std::pair<unsigned,unsigned>> events;unsigned f,c,d;
        std::ifstream replay(argv[2]);while(replay>>f>>c>>d)events[f]={c,d};
        std::ofstream inputs(prefix+".inputs.tsv"),states(prefix+".states.tsv");
        states<<"frame\troot\tplay\tsubstate\tstage\tmode\tall_clear\n";
        std::vector<uint8_t> pixels(240*320*4);
        auto snapshot=[&](const std::string &name) {futari_pixels(game,pixels.data());std::ofstream(prefix+"-"+name+".rgba",std::ios::binary).write((char*)pixels.data(),pixels.size());};
        auto step=[&](unsigned c,unsigned d){if(!futari_frame(game,c,d))throw std::runtime_error(futari_error(game));};
        auto replay90=[&]() {
            if(!futari_restart_stage(game))throw std::runtime_error("No current-stage checkpoint");
            futari::inspectNativeGame(game).graphics.observer=nullptr;
            CC_SHA256_CTX hash;CC_SHA256_Init(&hash);
            for(unsigned i=0;i<90;i++) {
                step(255,uint8_t(~(0x40|(i<30?4:i<60?8:0))));
                futari_pixels(game,pixels.data());CC_SHA256_Update(&hash,pixels.data(),unsigned(pixels.size()));
                unsigned count;auto samples=futari_audio(game,&count);CC_SHA256_Update(&hash,samples,count*sizeof(float));
            }
            std::array<unsigned char,32> digest{};CC_SHA256_Final(digest.data(),&hash);return digest;
        };
        std::array<uint64_t,5> entries{};std::array<std::string,5> restartHashes;
        uint32_t previousRoot=~0u,previousPlay=~0u,previousSub=~0u;int previousStage=-2;
        bool ending=false,returned=false;uint64_t endingFrame=0,returnFrame=0,audioSamples=0,nonzeroSamples=0;
        float peak=0;c=d=255;unsigned oldC=0,oldD=0;
        auto start=std::chrono::steady_clock::now();
        for(f=0;f<180000;f++) {
            auto before=futari::CampaignState::read(futari::inspectNativeGame(game));
            auto event=events.find(f);if(event!=events.end()){c=event->second.first;d=event->second.second;}
            if(f>=3300) {
                c=255;d=191;
                if(f>=3700){unsigned phase=(f-3700)%180;if(phase<12)c&=~4;if(phase>=30&&phase<42)c&=~16;}
                if(f>=3500&&(f-3500)%240<12)d&=~32;
            }
            if(ending) {c=d=255;if(before.phase==futari::CampaignPhase::Ranking&&f%90<3)d=239;}
            if(c!=oldC||d!=oldD){inputs<<f<<' '<<c<<' '<<d<<'\n';oldC=c;oldD=d;}
            assets.frame=f;assets.stage=before.phase==futari::CampaignPhase::Playing?before.stage:-1;
            futari::inspectNativeGame(game).graphics.observer=&assets;
            step(c,d);
            auto &board=futari::inspectNativeGame(game);auto state=futari::CampaignState::read(board);
            if(state.phase==futari::CampaignPhase::Playing&&state.mode!=0)throw std::runtime_error("Replay selected a mode other than Original");
            unsigned count;auto samples=futari_audio(game,&count);audioSamples+=count;
            for(unsigned i=0;i<count;i++){if(!std::isfinite(samples[i]))throw std::runtime_error("Non-finite audio");if(samples[i]!=0)++nonzeroSamples;peak=std::max(peak,std::abs(samples[i]));}
            if(state.root!=previousRoot||state.play!=previousPlay||state.substate!=previousSub||state.stage!=previousStage) {
                states<<f<<'\t'<<state.root<<'\t'<<state.play<<'\t'<<state.substate<<'\t'<<state.stage<<'\t'<<state.mode<<'\t'<<state.allClear<<'\n';states.flush();
                fprintf(stderr,"state frame=%u root=%u play=%u sub=%u stage=%d clear=%d\n",f,state.root,state.play,state.substate,state.stage,state.allClear);
                snapshot("state-"+std::to_string(f));
                previousRoot=state.root;previousPlay=state.play;previousSub=state.substate;previousStage=state.stage;
            }
            if(state.phase==futari::CampaignPhase::Playing&&state.stage>=0&&state.stage<5&&!entries[state.stage]) {
                entries[state.stage]=f;snapshot("stage-"+std::to_string(state.stage+1));
                auto first=replay90(),second=replay90();
                if(first!=second)throw std::runtime_error("Stage restart pixels/audio diverged");
                restartHashes[state.stage]=hexDigest(first.data(),first.size());
                if(!futari_restart_stage(game))throw std::runtime_error("Stage restore failed");
                assets.invalidate(); // Restoring a board replaces all VRAM contents.
            }
            if(state.play==7&&state.allClear&&!ending){ending=true;endingFrame=f;snapshot("ending-entry");}
            if(f%600==0){snapshot("frame-"+std::to_string(f));fprintf(stderr,"frame %u regions=%zu pages=%zu\n",f,assets.regions.size(),assets.matchedResources.size());}
            if(ending&&state.root==3){returned=true;returnFrame=f;snapshot("attract-return");break;}
            if(f>3500&&!ending&&state.root==3)throw std::runtime_error("Run ended before all clear");
        }
        assets.save(prefix);
        for(auto entry:entries)if(!entry)throw std::runtime_error("Did not enter every stage");
        if(!ending||!returned)throw std::runtime_error("Did not complete ending and return to attract");
        if(!futari_save_settings(game))throw std::runtime_error("Could not save final settings");
        std::ofstream report(prefix+".verification.json");
        report<<"{\"all_clear\":true,\"returned_to_attract\":true,\"ending_frame\":"<<endingFrame<<",\"attract_frame\":"<<returnFrame<<",\"stages\":[";
        for(unsigned i=0;i<5;i++){if(i)report<<',';report<<"{\"stage\":"<<i+1<<",\"entry_frame\":"<<entries[i]<<",\"restart_frames\":90,\"restart_pixels_audio_sha256\":\""<<restartHashes[i]<<"\"}";}
        report<<"],\"audio_samples\":"<<audioSamples<<",\"nonzero_audio_samples\":"<<nonzeroSamples<<",\"audio_peak\":"<<peak<<",\"elapsed_seconds\":"<<std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<<"}\n";
        futari_destroy(game);game=nullptr;puts("PASS: all five stages, five deterministic stage restarts, ending and return to attract");return 0;
    }catch(const std::exception &e){fprintf(stderr,"%s\n",e.what());if(game)futari_destroy(game);return 1;}
}
