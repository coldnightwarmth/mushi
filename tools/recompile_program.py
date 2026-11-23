#!/usr/bin/env python3
"""Build-time SH7709S -> C++ translation. No decoder is included in the app.

Every generated instruction has a fixed source address and fixed operands.
Indirect transfers dispatch to compiled pages; unsupported targets fail closed.
Generated game-specific source stays in ignored build/, like extracted assets.
"""
import argparse
import hashlib
import json
from pathlib import Path

BASE=0x0c000000
PAGE=1024

def sx(v,bits):
    return (v^(1<<(bits-1)))-(1<<(bits-1))

def literal(v):
    return f'0x{v&0xffffffff:08x}u'

def emit(op,pc,slot=False):
    """Return native statements, optional transfer, and delay-slot flag."""
    g=op>>12;n=(op>>8)&15;m=(op>>4)&15;k=op&15;lo=op&255
    N=f'r[{n}]';M=f'r[{m}]';I=literal(sx(lo,8));code=None;target=None;delay=False
    def T(x): return f'c.t({x});'
    def load(size,addr,dest):
        cast={'b':'int8_t','w':'int16_t','l':'uint32_t'}[size]
        return f'{dest}={cast}(c.r{size}({addr}));'
    if g==0:
        if k in (4,5,6): code=f'c.w{["b","w","l"][k-4]}({N}+r[0],{M});'
        elif k in (12,13,14): code=load(['b','w','l'][k-12],f'{M}+r[0]',N)
        elif k==7: code=f'c.macl={N}*{M};'
        elif k==15: code=f'c.mac({m},{n},false);'
        elif lo in (0x03,0x23):
            code=f'c.pr={literal(pc+4)};' if lo==3 else ''
            target=f'{N}+{literal(pc+4)}';delay=True
        elif op==0x000b: code='';target='c.pr';delay=True
        elif op==0x002b: code='c.status(c.ssr);';target='c.spc';delay=True
        elif op==0x0009: code=''
        elif op==0x0008: code='c.t(false);'
        elif op==0x0018: code='c.t(true);'
        elif op==0x0028: code='c.mach=c.macl=0;'
        elif op==0x0019: code='c.sr&=~0x301u;'
        elif lo==0x29: code=f'{N}=c.sr&1;'
        elif lo in (0x02,0x12,0x22,0x32,0x42): code=f'{N}=c.{["sr","gbr","vbr","ssr","spc"][lo>>4]};'
        elif lo in (0x0a,0x1a,0x2a): code=f'{N}=c.{["mach","macl","pr"][lo>>4]};'
        elif lo&0x8f==0x82: code=f'{N}=c.bank[{(lo>>4)&7}];'
        elif lo in (0x83,0x93,0xa3,0xb3) or op==0x0038: code='' # Cache/TLB operations; no virtual mappings used.
        elif op==0x001b: code='c.cycles=c.deadline;';target=literal(pc+2)
    elif g==1: code=f'c.wl({N}+{k*4},{M});'
    elif g==2:
        if k in (0,1,2): code=f'c.w{["b","w","l"][k]}({N},{M});'
        elif k in (4,5,6):
            size=1<<(k-4);code=f'{{uint32_t v={M};{N}-={size};c.w{["b","w","l"][k-4]}({N},v);}}'
        elif k==7: code=f'c.sr=(c.sr&~0x301u)|(({N}>>23)&0x100)|(({M}>>22)&0x200);'+T(f'(({N}^{M})>>31)!=0')
        elif k==8: code=T(f'({N}&{M})==0')
        elif k in (9,10,11): code=f'{N}{["&","^","|"][k-9]}={M};'
        elif k==12: code=f'{{uint32_t v={N}^{M};c.t(!(v&255)||!(v&0xff00)||!(v&0xff0000)||!(v&0xff000000));}}'
        elif k==13: code=f'{N}=({N}>>16)|({M}<<16);'
        elif k==14: code=f'c.macl=uint32_t(uint16_t({N}))*uint16_t({M});'
        elif k==15: code=f'c.macl=int32_t(int16_t({N}))*int16_t({M});'
    elif g==3:
        if k in (0,2,3,6,7):
            cmp={0:'==',2:'>=',3:'>=',6:'>',7:'>'}[k]
            a,b=(f'int32_t({N})',f'int32_t({M})') if k in (3,7) else (N,M)
            code=T(f'{a}{cmp}{b}')
        elif k==4: code=f'c.div1({m},{n});'
        elif k in (5,13):
            a,b=(f'int64_t(int32_t({N}))',f'int32_t({M})') if k==13 else (f'uint64_t({N})',M)
            code=f'{{uint64_t v={a}*{b};c.mach=v>>32;c.macl=v;}}'
        elif k in (8,12): code=f'{N}{"-" if k==8 else "+"}={M};'
        elif k in (10,14):
            if k==10: code=f'{{uint64_t sub=uint64_t({M})+(c.sr&1);uint32_t old={N};{N}-=sub;c.t(uint64_t(old)<sub);}}'
            else: code=f'{{uint64_t v=uint64_t({N})+{M}+(c.sr&1);{N}=v;c.t(v>>32);}}'
        elif k in (11,15):
            sign='-' if k==11 else '+'
            code=f'{{int64_t v=int64_t(int32_t({N})){sign}int32_t({M});{N}=v;c.t(v<INT32_MIN||v>INT32_MAX);}}'
    elif g==4:
        if k in (12,13):
            rhs=f'uint32_t(int32_t({N})>>s)' if k==12 else f'{N}>>s'
            large=f'uint32_t(int32_t({N})>>31)' if k==12 else '0'
            code=f'{{uint32_t v={M};if(!(v&0x80000000)) {N}<<=(v&31);else {{unsigned s=(-v)&31;{N}=s?{rhs}:{large};}}}}'
        elif k==15: code=f'c.mac({m},{n},true);'
        elif lo in (0x0b,0x2b):
            code=f'c.pr={literal(pc+4)};' if lo==0x0b else ''
            target=N;delay=True
        elif lo in (0x00,0x20): code=f'c.t({N}>>31);{N}<<=1;'
        elif lo in (0x01,0x21): code=f'c.t({N}&1);{N}={"uint32_t(int32_t("+N+")>>1)" if lo==0x21 else N+">>1"};'
        elif lo==0x04: code=f'c.t({N}>>31);{N}=({N}<<1)|({N}>>31);'
        elif lo==0x05: code=f'c.t({N}&1);{N}=({N}>>1)|({N}<<31);'
        elif lo==0x24: code=f'{{uint32_t t=c.sr&1;c.t({N}>>31);{N}=({N}<<1)|t;}}'
        elif lo==0x25: code=f'{{uint32_t t=c.sr&1;c.t({N}&1);{N}=({N}>>1)|(t<<31);}}'
        elif lo in (0x08,0x18,0x28): code=f'{N}<<={ {8:2,24:8,40:16}[lo]};'
        elif lo in (0x09,0x19,0x29): code=f'{N}>>={ {9:2,25:8,41:16}[lo]};'
        elif lo==0x10: code=f'--{N};c.t({N}==0);'
        elif lo==0x11: code=T(f'int32_t({N})>=0')
        elif lo==0x15: code=T(f'int32_t({N})>0')
        elif lo==0x1b: code=f'{{uint32_t v=c.rb({N});c.t(v==0);c.wb({N},v|128);}}'
        else:
            reg=None;mode=None
            if lo in (0x02,0x12,0x22,0x06,0x16,0x26,0x0a,0x1a,0x2a):
                reg='c.'+['mach','macl','pr'][lo>>4];mode={2:'store',6:'load',10:'assign'}[lo&15]
            elif lo in (0x03,0x13,0x23,0x33,0x43,0x07,0x17,0x27,0x37,0x47,0x0e,0x1e,0x2e,0x3e,0x4e):
                reg='c.'+['sr','gbr','vbr','ssr','spc'][lo>>4];mode={3:'store',7:'load',14:'assign'}[lo&15]
            elif lo&0x8f in (0x83,0x87,0x8e):
                reg=f'c.bank[{(lo>>4)&7}]';mode={3:'store',7:'load',14:'assign'}[lo&15]
            if reg:
                if mode=='store': code=f'{{uint32_t v={reg};{N}-=4;c.wl({N},v);}}'
                elif mode=='load':
                    code=(f'c.status(c.rl({N}));' if reg=='c.sr' else f'{reg}=c.rl({N});')+f'{N}+=4;'
                else: code=f'c.status({N});' if reg=='c.sr' else f'{reg}={N};'
    elif g==5: code=load('l',f'{M}+{k*4}',N)
    elif g==6:
        if k in (0,1,2,4,5,6):
            size=['b','w','l'][k%4];code=load(size,M,N)
            if k>=4 and n!=m: code+=f'{M}+={1<<(k-4)};'
        elif k==3: code=f'{N}={M};'
        elif k==7: code=f'{N}=~{M};'
        elif k==8: code=f'{N}=({M}&0xffff0000)|(({M}&255)<<8)|(({M}>>8)&255);'
        elif k==9: code=f'{N}=({M}<<16)|({M}>>16);'
        elif k==10: code=f'{{uint64_t v=uint64_t({M})+(c.sr&1);{N}=0-uint32_t(v);c.t(v!=0);}}'
        elif k==11: code=f'{N}=0-{M};'
        else: code=f'{N}={ {12:"uint8_t",13:"uint16_t",14:"int8_t",15:"int16_t"}[k]}({M});'
    elif g==7: code=f'{N}+={I};'
    elif g==8:
        if n in (0,1): code=f'c.w{["b","w"][n]}({M}+{k*(n+1)},r[0]);'
        elif n in (4,5): code=load(['b','w'][n-4],f'{M}+{k*(n-3)}','r[0]')
        elif n==8: code=T(f'r[0]=={I}')
        elif n in (9,11,13,15):
            cond='(c.sr&1)' if n in (9,13) else '!(c.sr&1)'
            delay=n>=13;target=f'{cond}?{literal(pc+4+2*sx(lo,8))}:{literal(pc+(4 if delay else 2))}';code=''
    elif g==9: code=load('w',f'next+{2+lo*2}' if slot else literal(pc+4+lo*2),N)
    elif g in (10,11):
        code=f'c.pr={literal(pc+4)};' if g==11 else '';target=literal(pc+4+2*sx(op&4095,12));delay=True
    elif g==12:
        if n in (0,1,2): code=f'c.w{["b","w","l"][n]}(c.gbr+{lo*(1<<n)},r[0]);'
        elif n in (4,5,6): code=load(['b','w','l'][n-4],f'c.gbr+{lo*(1<<(n-4))}','r[0]')
        elif n==7: code=f'r[0]={"((next+2)&~3u)+"+str(lo*4) if slot else literal(((pc+4)&~3)+lo*4)};'
        elif n==8: code=T(f'(r[0]&{lo})==0')
        elif n in (9,10,11): code=f'r[0]{["&","^","|"][n-9]}={lo};'
        elif n==12: code=T(f'(c.rb(c.gbr+r[0])&{lo})==0')
        elif n in (13,14,15): code=f'c.wb(c.gbr+r[0],c.rb(c.gbr+r[0]){["&","^","|"][n-13]}{lo});'
        elif n==3:
            code=f'c.wl(0xffffffd0,{lo*4});c.wl(0xffffffd4,0x160);c.ssr=c.sr;c.spc={literal(pc+2)};c.status(c.sr|0x70000000);';target='c.vbr+0x100'
    elif g==13: code=load('l',f'((next+2)&~3u)+{lo*4}' if slot else literal(((pc+4)&~3)+lo*4),N)
    elif g==14: code=f'{N}={I};'
    return code,target,delay

def generate(program,out,end):
    data=program.read_bytes();out.mkdir(parents=True,exist_ok=True)
    ram_code=bytearray(data)
    # Startup copies these three vector stubs from ROM to RAM. Compile their
    # destination forms as well as the distinct, immutable ROM boot page.
    for source,destination,length in [(0x1dc,0x100,16),(0x1ec,0x400,16),(0x1fc,0x600,20)]:
        ram_code[destination:destination+length]=data[source:source+length]
    pages=[];supported=0
    def ins(pc,slot=False):
        off=pc-BASE if pc>=BASE else pc
        if off<0 or off+2>len(data): return None,None,False
        image=ram_code if pc>=BASE else data
        return emit(int.from_bytes(image[off:off+2],'big'),pc,slot)
    for start in [0]+list(range(BASE,BASE+end,PAGE)):
        lines=[f'void page_{start:x}(CompiledState &c) {{', 'auto &r=c.r; unsigned cost=0; switch(c.pc) {']
        for pc in range(start,min(start+PAGE,BASE+end),2):
            code,target,delay=ins(pc)
            if delay:
                slot,branch,_=ins(pc+2,True)
                if slot is None or branch is not None: code=None
            if code is None:
                lines.append(f'case 0x{pc:x}: c.missing(0x{pc:x});')
                continue
            supported+=1
            lines.append(f'case 0x{pc:x}: {{ ++cost;')
            # Reviewed optional custom-play seams. With no host hook these emit
            # the identical original operations; no runtime decoding is added.
            if pc in (0x0c07900e,0x0c07902a,0x0c079036,0x0c079e86,0x0c09b912,0x0c09c712,0x0c09c6fe,0x0c09c706):
                lines.append(f'if(c.bus->nativeHook(0x{pc:x},c)){{c.cycles+=cost;return;}}')
            if target is not None:
                # Capture targets before the slot or a bank change can alter operands.
                lines.append(f'uint32_t next={target}; {code}')
                if delay: lines.append(f'{slot} ++cost;')
                lines.append('c.pc=next;c.cycles+=cost;return;}')
            else:
                lines.append(code+'}')
                nextCode,_,_=ins(pc+2)
                if pc+2>=min(start+PAGE,BASE+end) or nextCode is None:
                    lines.append(f'c.pc=0x{pc+2:x};c.cycles+=cost;return;')
        lines+=['default: c.missing(c.pc);','}}']
        pages.append((start,'\n'.join(lines)))
    files=[]
    for index in range(0,len(pages),8):
        path=out/f'pages_{index//8:03d}.cpp'
        contents='#include "CompiledState.hpp"\nnamespace futari {\n'+'\n'.join(code for _,code in pages[index:index+8])+'\n}\n'
        if not path.exists() or path.read_text()!=contents: path.write_text(contents)
        files.append(path.name)
    declarations='\n'.join(f'void page_{p:x}(CompiledState &);' for p,_ in pages)
    table=','.join(f'page_{p:x}' for p,_ in pages if p>=BASE)
    dispatch=f'''#include "CompiledState.hpp"
#include "RecoveredDrawQueue.hpp"
namespace futari {{
{declarations}
static NativePage pages[]={{{table}}};
#ifdef FUTARI_ORIGINAL_DISPATCH
void runCompiledOriginal(CompiledState &c,uint64_t deadline) {{
#else
void runCompiled(CompiledState &c,uint64_t deadline) {{
#endif
 c.deadline=deadline;
 while(c.cycles<deadline) {{
  uint32_t physical=c.pc&0x1fffffff;
  c.pc=physical;
  if(physical<{PAGE}) {{page_0(c);continue;}}
#ifndef FUTARI_ORIGINAL_DISPATCH
  // A whole recovered call must fit before the host interrupt boundary.
  // Short slices retain the original basic-block boundaries and scratch state.
  if(physical==0x0c05c394 && deadline-c.cycles>=28) {{
   recovered::DrawQueue::call(c);continue;
  }}
#endif
  // Reviewed frame-counter wait loop. No memory it observes changes until
  // the host services an interrupt at this slice boundary. Preserve the
  // final loop register/flag state while eliding redundant polling.
  if(physical==0x0c05176a && c.r[4]>uint32_t(c.r[0]-c.r[1])) {{
   c.t(true);c.r[0]=c.rl(c.r[2]);c.cycles=deadline;continue;
  }}
  if(physical<0x0c000000||physical>=0x{BASE+end:x}||(physical&1)) c.missing(physical);
  pages[(physical-0x0c000000)/{PAGE}](c);
 }}
}}
}}
'''
    (out/'dispatch.cpp').write_text(dispatch)
    (out/'manifest.json').write_text(json.dumps({'program_sha256':hashlib.sha256(data).hexdigest(),'translator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'instructions':supported,'pages':len(pages),'sources':files+['dispatch.cpp']},indent=2)+'\n')
    print(f'Generated {supported:,} instruction sites in {len(files)} native source files')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--program',type=Path,default=Path('build/program/expanded.bin'));p.add_argument('--out',type=Path,default=Path('build/aot/generated'));p.add_argument('--end',type=lambda s:int(s,0),default=0x1e0000)
    a=p.parse_args();generate(a.program,a.out,a.end)
