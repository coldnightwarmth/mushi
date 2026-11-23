#include "Audio.hpp"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <stdexcept>

// Offline extraction uses the same native AMM decoder as the game. Nothing is
// sent to a speaker, and duplicate directory entries share one decoded file.
static void le(std::ostream &out,uint32_t n,unsigned bytes){for(unsigned i=0;i<bytes;i++)out.put(char(n>>(i*8)));}
static void wav(const std::filesystem::path &path,const std::vector<int16_t> &samples,unsigned channels){
 std::ofstream out(path,std::ios::binary);out.write("RIFF",4);le(out,36+samples.size()*2,4);out.write("WAVEfmt ",8);le(out,16,4);le(out,1,2);le(out,channels,2);
 // YMZ770 playback uses the board's 16 kHz sample clock, independently of the
 // MPEG-derived rate field retained below as provenance.
 le(out,16000,4);le(out,16000*channels*2,4);le(out,channels*2,2);le(out,16,2);out.write("data",4);le(out,samples.size()*2,4);
 for(auto sample:samples)le(out,uint16_t(sample),2);
 if(!out)throw std::runtime_error("Cannot write WAV");
}
int main(int argc,char **argv){try{
 if(argc!=3)return 2;
 std::ifstream input(argv[1],std::ios::binary);std::vector<uint8_t> rom((std::istreambuf_iterator<char>(input)),{});
 if(rom.size()!=0x800000)throw std::runtime_error("Expected verified, word-swapped u23/u24 sound bank");
 std::filesystem::path out=argv[2];std::filesystem::create_directories(out);
 auto word=[&](unsigned at){return uint32_t(rom.at(at))<<24|uint32_t(rom.at(at+1))<<16|uint32_t(rom.at(at+2))<<8|rom.at(at+3);};
 std::set<uint32_t> boundaries;for(unsigned i=0;i<256;i++)boundaries.insert(word(i*4)&0xffffff);
 boundaries.insert(rom.size());std::map<uint32_t,unsigned> seen;
 std::ofstream index(out/"phrases.tsv");index<<"index\tentry\talias\toffset\tend_bit\tframes\tsamples\tchannels\theader_rates\tterminated\n";
 for(unsigned i=0;i<256;i++){
  auto entry=word(i*4),offset=entry&0xffffff;auto prior=seen.find(entry);
  if(prior!=seen.end()){index<<i<<'\t'<<entry<<'\t'<<prior->second<<'\t'<<offset<<"\t0\t0\t0\t0\t\talias\n";continue;}
  seen[entry]=i;auto boundary=boundaries.upper_bound(offset);if(boundary==boundaries.end())throw std::runtime_error("Invalid phrase offset");
  int position=offset*8,limit=*boundary*8,channels=0;bool terminated=false;unsigned frames=0;
  std::vector<int16_t> samples;std::set<int> rates;mpeg_audio decoder(rom.data(),mpeg_audio::AMM,false,0);
  while(position<limit){
   int count=0,rate=0,ch=0;int16_t decoded[4096]{};int previous=position;
   if(!decoder.decode_buffer(position,limit,decoded,count,rate,ch,(entry>>28)&7))break;
   if(position<=previous||count<0||count*ch>4096||ch<1||ch>2)throw std::runtime_error("Invalid decoded phrase");
   if(channels&&channels!=ch&&count)throw std::runtime_error("Changing phrase channel count");
   if(count){channels=ch;rates.insert(rate);samples.insert(samples.end(),decoded,decoded+count*ch);++frames;}
   if(count<1152){terminated=true;break;}
   if(samples.size()>16000*600*2)throw std::runtime_error("Unbounded phrase");
  }
  if(!terminated)throw std::runtime_error("Phrase "+std::to_string(i)+" crossed its directory boundary without ending");
  if(channels==1){
   futari::Audio native(rom);
   auto reg=[&](uint8_t address,uint8_t value){native.write(0,address);native.write(1,value);};
   reg(1,128);reg(0x40,i);reg(0x41,128);reg(0x42,16);reg(0x43,2);
   for(auto sample:samples)if(native.sample()*32768.f!=sample)throw std::runtime_error("Native mixer/phrase decode mismatch");
   for(int tail=0;tail<16;tail++)if(native.sample()!=0)throw std::runtime_error("Native phrase did not end at extracted boundary");
  }
  if(channels)wav(out/("phrase-"+std::to_string(i)+".wav"),samples,channels);
  index<<i<<'\t'<<entry<<"\t-1\t"<<offset<<'\t'<<position<<'\t'<<frames<<'\t'<<samples.size()<<'\t'<<channels<<'\t';
  for(int rate:rates)index<<rate<<',';index<<"\tend-marker\n";
 }
 std::cout<<"Decoded "<<seen.size()<<" unique sound-directory entries from 256 phrases\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
