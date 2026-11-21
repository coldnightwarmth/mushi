#pragma once
#include "Graphics.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <cstring>
#include <fstream>
#include <map>
#include <set>

// Match complete source pages, never guessed sprite grids. Dirty destination
// pages invalidate the cache before any subsequent draw can use them as a source.
struct NativeAssets final:futari::GraphicsObserver {
    using Digest=std::array<unsigned char,CC_SHA256_DIGEST_LENGTH>;
    using Key=std::array<int,7>; // resource, x, y, width, height, attributes, stage
    struct Evidence {uint64_t first=0,last=0,count=0;uint32_t command=0;};
    std::map<Digest,int> resources;
    std::array<int,512> pages;
    std::array<uint32_t,256*256> scratch;
    std::map<Key,Evidence> regions;
    std::set<int> matchedResources;
    std::array<uint64_t,6> mapped{},unmapped{}; // index zero is menus/ending
    uint64_t frame=0,hashedPages=0;
    int stage=-1;
    explicit NativeAssets(const std::string &hashFile) {
        pages.fill(-2);
        std::ifstream in(hashFile);std::string hex;int index;
        while(in>>index>>hex) {
            if(hex.size()!=64)throw std::runtime_error("Invalid resource hash file");
            Digest d{};for(unsigned i=0;i<d.size();i++)d[i]=std::stoul(hex.substr(i*2,2),nullptr,16);
            resources[d]=index;
        }
        if(resources.size()!=1201)throw std::runtime_error("Expected all 1201 resource hashes");
    }
    void invalidate() {pages.fill(-2);}
    void written(int x,int y,int w,int h) override {
        for(int py=y/256;py<=(y+h-1)/256;py++)
            for(int px=x/256;px<=(x+w-1)/256;px++)pages[(py&15)*32+(px&31)]=-2;
    }
    void draw(const futari::Graphics &g,uint32_t address,uint16_t attributes,int x,int y,int w,int h) override {
        unsigned context=stage>=0&&stage<5?unsigned(stage+1):0;
        if((x&255)+w>256||(y&255)+h>256){++unmapped[context];return;}
        int page=(y/256)*32+x/256;
        if(pages[page]==-2) {
            int px=x&~255,py=y&~255;
            for(int row=0;row<256;row++)std::memcpy(scratch.data()+row*256,g.pixels.data()+(py+row)*8192+px,256*4);
            Digest digest{};CC_SHA256(scratch.data(),unsigned(scratch.size()*4),digest.data());++hashedPages;
            auto match=resources.find(digest);pages[page]=match==resources.end()?-1:match->second;
        }
        if(pages[page]<0){++unmapped[context];return;}
        ++mapped[context];matchedResources.insert(pages[page]);
        Key key{{pages[page],x&255,y&255,w,h,attributes,stage}};
        auto &e=regions[key];if(!e.count){e.first=frame;e.command=address;}e.last=frame;++e.count;
    }
    void save(const std::string &prefix) const {
        std::ofstream out(prefix+".regions.tsv");
        out<<"resource\tx\ty\twidth\theight\tattributes\tstage\tfirst_frame\tlast_frame\tdraws\tcommand_address\n";
        for(const auto &[k,e]:regions){for(int v:k)out<<v<<'\t';out<<e.first<<'\t'<<e.last<<'\t'<<e.count<<'\t'<<e.command<<'\n';}
        std::ofstream stats(prefix+".assets.json");
        stats<<"{\"hashed_pages\":"<<hashedPages<<",\"matched_resources\":[";
        bool comma=false;for(int r:matchedResources){if(comma)stats<<',';stats<<r;comma=true;}
        stats<<"],\"contexts\":[";
        for(unsigned i=0;i<6;i++){if(i)stats<<',';stats<<"{\"stage\":"<<int(i)-1<<",\"mapped_draws\":"<<mapped[i]<<",\"unmapped_draws\":"<<unmapped[i]<<'}';}
        stats<<"]}\n";
    }
};
