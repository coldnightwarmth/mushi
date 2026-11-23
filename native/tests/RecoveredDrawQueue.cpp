#include "RecoveredDrawQueue.hpp"
#include <fstream>
#include <vector>
#include <array>
#include <cstring>
#include <iostream>

struct Memory:futari::Bus {
 std::vector<uint8_t> bytes=std::vector<uint8_t>(0x800000);
 std::vector<std::array<uint32_t,3>> writes;
 uint32_t read(uint32_t a,unsigned n)override{uint32_t v=0;for(unsigned i=0;i<n;i++)v=v<<8|bytes.at((a&0x7fffff)+i);return v;}
 void write(uint32_t a,uint32_t v,unsigned n)override{writes.push_back({a,v,n});for(unsigned i=0;i<n;i++)bytes.at((a&0x7fffff)+i)=v>>((n-1-i)*8);}
};
int main(int argc,char **argv){try{
 if(argc!=2)return 2;
 Memory seed,original,native;std::ifstream file(argv[1],std::ios::binary);file.read((char*)seed.bytes.data(),seed.bytes.size());
 uint32_t random=0x154cafe;auto next=[&](){random^=random<<13;random^=random>>17;random^=random<<5;return random;};
 unsigned checks=0;
 for(unsigned priority=0;priority<512;priority++)for(unsigned situation=0;situation<3;situation++){
  original.bytes=seed.bytes;
  auto used=situation==2 ? 0x17700u:(next()%5999+1)*16;
  auto bucket=0xc058340+priority*8;
  original.write(0xc058338,0xc600000,4);original.write(0xc05833c,used,4);
  original.write(bucket,situation==1?0xc600000:0,4);original.write(bucket+4,situation==1?0xc600000:0,4);
  // Poison unused bytes: neither implementation may invent extra clearing.
  for(unsigned i=0;i<16;i++)original.bytes[0x600000+used+i]=next();
  futari::CompiledState a;for(auto &r:a.r)r=next();for(auto &r:a.bank)r=next();
  a.r[4]=next();a.r[5]=next();a.r[6]=priority|0xfffffe00u;a.r[15]=0xc7fe000;
  a.pc=0xc05c394;a.pr=0xc7ff000;a.sr=next();a.cycles=23;a.deadline=1000;
  auto b=a;native.bytes=original.bytes;a.bus=&original;b.bus=&native;original.writes.clear();native.writes.clear();
  try{futari::runCompiled(a,1000);}catch(const std::exception &){if(a.pc!=a.pr)throw;}
  futari::recovered::DrawQueue::call(b);
  if(a.pc!=b.pc||a.sr!=b.sr||a.cycles!=b.cycles||std::memcmp(a.r,b.r,sizeof(a.r))||std::memcmp(a.bank,b.bank,sizeof(a.bank))||original.bytes!=native.bytes||original.writes!=native.writes){
   std::cerr<<"Mismatch priority="<<priority<<" situation="<<situation<<" cycles="<<a.cycles<<'/'<<b.cycles<<'\n';return 1;
  }
  ++checks;
 }
 std::cout<<"PASS "<<checks<<" draw-queue cases: all priority buckets, empty/nonempty/full, every RAM byte, write order, registers, flags and instruction counts\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
