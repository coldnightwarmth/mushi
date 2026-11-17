#!/usr/bin/env python3
"""Differential AOT arithmetic verification, including signed divide steps."""
import argparse,json,random,struct,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from mushi.reference import HEADLESS_OPTIONS,headless_environment
from recompile_program import emit

def main():
    p=argparse.ArgumentParser();p.add_argument('--mame',type=Path,required=True);p.add_argument('--rom',type=Path,required=True);p.add_argument('--frameworks',type=Path);a=p.parse_args()
    out=ROOT/'build/aot-alu';out.mkdir(parents=True,exist_ok=True)
    opcodes=set()
    for m in [4,5]:
        for low in [3,7,8,9,10,11,12,13,14,15]:opcodes.add(0x6400|(m<<4)|low)
        for low in [7,8,9,10,11,12,13,14,15]:opcodes.add(0x2400|(m<<4)|low)
        for low in [0,2,3,4,5,6,7,8,10,11,12,13,14,15]:opcodes.add(0x3400|(m<<4)|low)
        for low in [12,13]:opcodes.add(0x4400|(m<<4)|low)
        opcodes.add(0x0407|(m<<4))
    for low in [0,1,4,5,8,9,16,17,21,24,25,32,33,36,37,40,41]:opcodes.add(0x4400|low)
    opcodes.update([0x0008,0x0018,0x0028,0x0019,0x0429,0x040a,0x041a,0x042a,0x7400,0x747f,0x7480,0x74ff,0xe47f,0xe480,0xc87f,0xc9fa,0xca55,0xcb91,0x8880])
    rng=random.Random(154);cases=[];values=[0,1,0xffffffff,0x80000000,0x7fffffff,31,32,33,0xffffffe0]
    for op in sorted(opcodes):
        for i in range(24):
            regs=[rng.getrandbits(32) for _ in range(16)];regs[15]=0x0c7fe000
            regs[4]=values[i%len(values)] if i<18 else rng.getrandbits(32)
            regs[5]=values[(i//len(values)+i)%len(values)] if i<18 else rng.getrandbits(32)
            sr=0x700000f0|((i&1)<<8)|((i&2)<<8)|((i>>2)&1)
            cases.append(struct.pack('>20I',op,*regs,sr,rng.getrandbits(32),rng.getrandbits(32)))
    (out/'cases.bin').write_bytes(b''.join(cases))
    functions=[];entries=[]
    for op in sorted(opcodes):
        code,target,delay=emit(op,0x0c7fc000);assert code is not None and target is None
        functions.append(f'void op_{op:x}(futari::CompiledState &c){{auto &r=c.r;{code}}}')
        entries.append(f'case 0x{op:x}:op_{op:x}(c);break;')
    source='''#include "CompiledState.hpp"
#include <fstream>
'''+ '\n'.join(functions)+'''
int main(int argc,char**argv){std::ifstream in(argv[1],std::ios::binary);std::ofstream out(argv[2],std::ios::binary);
auto read=[&](){unsigned char b[4];in.read((char*)b,4);return (uint32_t(b[0])<<24)|(uint32_t(b[1])<<16)|(uint32_t(b[2])<<8)|b[3];};
auto write=[&](uint32_t v){unsigned char b[4]={uint8_t(v>>24),uint8_t(v>>16),uint8_t(v>>8),uint8_t(v)};out.write((char*)b,4);};
while(in.peek()!=EOF){uint32_t op=read();futari::CompiledState c;for(auto &r:c.r)r=read();c.sr=read();c.mach=read();c.macl=read();c.pr=0x0c7ff000;
switch(op){'''+''.join(entries)+'''}
for(auto r:c.r)write(r);write(c.sr);write(c.mach);write(c.macl);}}
'''
    (out/'alu.cpp').write_text(source)
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-I',str(ROOT/'native/core'),str(out/'alu.cpp'),'-o',str(out/'VerifyALU')],check=True)
    subprocess.run([str(out/'VerifyALU'),str(out/'cases.bin'),str(out/'native.bin')],check=True)
    env=headless_environment(a.frameworks);env['MUSHI_ALU_TEST']=str(out)
    cmd=[str(a.mame),'futari15','-rompath',str(a.rom.parent),*HEADLESS_OPTIONS,'-verbose','-nothrottle','-nodrc','-skip_gameinfo','-autoboot_delay','0','-autoboot_script',str(ROOT/'tools/verify_aot_alu.lua'),'-cfg_directory',str(out/'cfg'),'-nvram_directory',str(out/'nvram'),'-seconds_to_run',str(len(cases)//50+20)]
    with (out/'oracle.log').open('w') as log:subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=240)
    native=(out/'native.bin').read_bytes();original=(out/'original.bin').read_bytes()
    assert len(original)==len(cases)*76,(len(original),len(cases)*76)
    failures=[]
    for i in range(len(cases)):
        if native[i*76:(i+1)*76]!=original[i*76:(i+1)*76]:
            op=struct.unpack_from('>I',cases[i])[0]
            failures.append(dict(case=i,op=f'{op:04x}',input=struct.unpack('>20I',cases[i]),native=struct.unpack_from('>19I',native,i*76),original=struct.unpack_from('>19I',original,i*76)))
    report=dict(cases=len(cases),opcodes=len(opcodes),failures=failures,exact=not failures)
    (out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'{len(cases)} AOT arithmetic cases, {len(failures)} failures')
    if failures:print(json.dumps(failures[:4],indent=2));sys.exit(1)
if __name__=='__main__':main()
