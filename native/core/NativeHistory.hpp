#pragma once
#include "Board.hpp"
#include <compression.h>
#include <deque>
#include <bitset>
#include <cstring>
namespace futari {
struct PackedMemory {
 std::vector<uint8_t> data;size_t count=0;bool compressed=false;
 void pack(const void *source,size_t n) {
  count=n;data.resize(n+n/255+128);
  size_t z=n?compression_encode_buffer(data.data(),data.size(),static_cast<const uint8_t*>(source),n,nullptr,COMPRESSION_LZ4):0;
  compressed=z&&z<n;
  // resize alone retains the large encoder allocation and defeats the history
  // budget. Store the packed bytes in an allocation sized to the result.
  if(compressed)data=std::vector<uint8_t>(data.begin(),data.begin()+z);
  else {data.resize(n);if(n)std::memcpy(data.data(),source,n);}
 }
 void unpack(void *dest)const {
  if(!compressed){if(count)std::memcpy(dest,data.data(),count);return;}
  if(compression_decode_buffer(static_cast<uint8_t*>(dest),count,data.data(),data.size(),nullptr,COMPRESSION_LZ4)!=count)throw std::runtime_error("Invalid native rewind record");
 }
};
class NativeHistory {
 struct Entry {
  std::unique_ptr<Board> core;PackedMemory ram,tiles;std::vector<uint32_t> ids,ramIds;unsigned formationPulse=0;uint64_t absorbed=0;
  size_t bytes()const {
   // Audio owns eight independently copied AMM decoders in addition to its
   // inline sample arrays. Include capacities, IO nodes and allocation slack.
   size_t device=sizeof(Board)+sizeof(Audio)+8*sizeof(mpeg_audio)+16*1024;
   if(core)device+=core->audioFrame.capacity()*sizeof(float)+core->io.size()*64+core->io.bucket_count()*sizeof(void*);
   return ram.data.capacity()+tiles.data.capacity()+(ids.capacity()+ramIds.capacity())*4+device;
  }
 };
 std::deque<Entry> entries;Entry pending;
 std::bitset<32768> saved;std::bitset<2048> savedRAM;
 std::vector<uint32_t> tileData;std::vector<uint8_t> ramData;size_t stored=0;
public:
 unsigned count()const{return unsigned(entries.size());}
 size_t bytes()const{return stored+tileData.capacity()*4+ramData.capacity();}
 void clear(){entries.clear();stored=0;pending={};tileData.clear();saved.reset();}
 void begin(Board &b,unsigned formationPulse,uint64_t absorbed) {
  pending.formationPulse=formationPulse;pending.absorbed=absorbed;
  auto pixels=std::move(b.graphics.pixels);auto ram=std::move(b.ram);
  try{pending.core=b.checkpoint();}catch(...){b.graphics.pixels=std::move(pixels);b.ram=std::move(ram);throw;}
  b.graphics.pixels=std::move(pixels);b.ram=std::move(ram);
  pending.core->hooks=nullptr;pending.core->graphics.observer=nullptr;
  pending.ids.clear();pending.ramIds.clear();tileData.clear();ramData.clear();saved.reset();savedRAM.reset();
 }
 void beforeRAMWrite(const Board &b,uint32_t address,unsigned size) {
  if(!pending.core||address<0xc000000||address+size>0xc800000)return;
  unsigned first=(address-0xc000000)/4096,last=(address-0xc000000+size-1)/4096;
  for(unsigned page=first;page<=last;page++)if(!savedRAM[page]) {
   savedRAM.set(page);pending.ramIds.push_back(page);
   ramData.insert(ramData.end(),b.ram.data()+page*4096,b.ram.data()+(page+1)*4096);
  }
 }
 void beforeWrite(const Graphics &g,int x,int y,int w,int h) {
  if(!pending.core)return;
  for(int yy=y/32;yy<=(y+h-1)/32;yy++)for(int xx=x/32;xx<=(x+w-1)/32;xx++) {
   unsigned tx=xx&255,ty=yy&127,id=ty*256+tx;if(saved[id])continue;saved.set(id);pending.ids.push_back(id);
   for(unsigned row=0;row<32;row++){auto p=g.pixels.data()+(ty*32+row)*8192+tx*32;tileData.insert(tileData.end(),p,p+32);}
  }
 }
 void finish() {
  if(!pending.core)return;
  pending.ram.pack(ramData.data(),ramData.size());pending.tiles.pack(tileData.data(),tileData.size()*4);stored+=pending.bytes();entries.push_back(std::move(pending));pending={};
  while(entries.size()>1&&(entries.size()>600||bytes()>192*1024*1024)){stored-=entries.front().bytes();entries.pop_front();}
 }
 bool pop(std::unique_ptr<Board> &b,unsigned &formationPulse,uint64_t &absorbed) {
  if(entries.empty())return false;
  Entry e=std::move(entries.back());entries.pop_back();stored-=e.bytes();
  formationPulse=e.formationPulse;absorbed=e.absorbed;
  auto pixels=std::move(b->graphics.pixels);auto ram=std::move(b->ram);auto settings=b->eeprom;
  tileData.resize(e.tiles.count/4);e.tiles.unpack(tileData.data());
  size_t at=0;for(auto id:e.ids){unsigned tx=id%256,ty=id/256;for(unsigned row=0;row<32;row++){std::memcpy(pixels.data()+(ty*32+row)*8192+tx*32,tileData.data()+at,128);at+=32;}}
  ramData.resize(e.ram.count);e.ram.unpack(ramData.data());at=0;
  for(auto page:e.ramIds){std::memcpy(ram.data()+page*4096,ramData.data()+at,4096);at+=4096;}
  b=std::move(e.core);b->graphics.pixels=std::move(pixels);b->ram=std::move(ram);b->state.bus=b.get();b->eeprom=settings;
  return true;
 }
};
}
