#!/usr/bin/env python3
"""Compare native renderer with a headless reference device, every blend mode."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from mushi.reference import HEADLESS_OPTIONS,headless_environment

def main():
    p=argparse.ArgumentParser();p.add_argument('--rom',type=Path,required=True);p.add_argument('--mame',type=Path,required=True);p.add_argument('--frameworks',type=Path);a=p.parse_args()
    out=ROOT/'build/native-graphics';out.mkdir(parents=True,exist_ok=True)
    commands=bytearray(struct.pack('>II',100,100))
    def words(*v):commands.extend(struct.pack('>'+len(v)*'H',*(x&65535 for x in v)))
    def upload(x,y,w,h,pixels):words(0x2000,0,0x9999,0x9999,x,y,w-1,h-1,*pixels)
    rng=random.Random(154);source=[rng.randrange(65536) for _ in range(256)]
    upload(7000,0,16,16,source);words(0xc000,0)
    count=0
    for flip in range(4):
        for transparent in range(2):
            for tinted in range(2):
                for sm in range(8):
                    for dm in range(8):
                        x=(count%256)*16;y=(count//256)*16
                        upload(x,y,16,16,[rng.randrange(65536) for _ in range(256)])
                        words(0x1200|(flip<<10)|(transparent<<8)|(sm<<4)|dm,rng.randrange(65536),7000,0,x,y,15,15,0x47 if tinted else 0x80,0xa0ed if tinted else 0x8080)
                        count+=1
    # Unblended transparent/tinted copies and explicit clipping at each edge.
    for flip in range(4):
        for trans in range(2):
            for tint in range(2):
                x=flip*40;y=200+trans*40+tint*20
                words(0x1000|(flip<<10)|(trans<<8),0,7000,0,x,y,15,15,0x40 if tint else 0x80,0xf010 if tint else 0x8080)
                count+=1
    words(0xc000,1)
    for x,y in [(62,100),(100,62),(445,100),(100,365),(-5,-5)]:
        words(0x1000,0,7000,0,x,y,15,15,0x80,0x8080);count+=1
    words(0xf000,0)
    (out/'commands.bin').write_bytes(commands)
    exe=out/'GraphicsVerification'
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-I',str(ROOT/'native/core'),str(ROOT/'native/core/Graphics.cpp'),str(ROOT/'native/tests/GraphicsVerification.cpp'),'-o',str(exe)],check=True)
    subprocess.run([str(exe),str(out/'commands.bin'),str(out/'native.bin')],check=True)
    env=headless_environment(a.frameworks);env['MUSHI_GRAPHICS_TEST']=str(out)
    cmd=[str(a.mame),'futari15','-rompath',str(a.rom.parent),*HEADLESS_OPTIONS,'-verbose','-nothrottle','-skip_gameinfo','-autoboot_delay','0','-autoboot_script',str(ROOT/'tools/verify_graphics.lua'),'-cfg_directory',str(out/'cfg'),'-nvram_directory',str(out/'nvram'),'-seconds_to_run','10']
    with (out/'oracle.log').open('w') as log:subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
    import numpy as np
    native=np.memmap(out/'native.bin',dtype='<u4',mode='r');reference=np.memmap(out/'original.bin',dtype='<u4',mode='r')
    bad=np.flatnonzero(native!=reference)
    if len(bad):
        for i in bad[:12]:print(f'Pixel {i%8192},{i//8192}: native={int(native[i]):08x} original={int(reference[i]):08x}')
        raise RuntimeError(f'{len(bad)} pixels differ')
    result=dict(draw_cases=count,blend_pairs=64,compared_pixels=len(native),exact=True,commands_sha256=hashlib.sha256(commands).hexdigest(),oracle_video_driver='dummy')
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

if __name__=='__main__':main()
