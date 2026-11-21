#!/usr/bin/env python3
"""Verify Futari's custom-play adapter and offscreen Mac menu; no emulator or GUI."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
from verify_native_playthroughs import ROUTES, convert_replay

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/custom-verified')
    parser.add_argument('--app',type=Path,default=ROOT/'build/macos/Mushihimesama Futari.app')
    parser.add_argument('--jobs',type=int,default=2)
    parser.add_argument('--checks',nargs='+',choices=['routes','combined','endless','campaign','menu'],default=['routes','combined','endless','campaign','menu'])
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    resources=ROOT/'build/aot/resources';exe=out/'NativeCustom'
    sources=['Board.cpp','Graphics.cpp','Audio.cpp','NativeGame.cpp','NativePresentation.cpp']
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-I',str(ROOT/'native/core'),*[str(ROOT/'native/core'/s) for s in sources],
                    str(ROOT/'native/vendor/mpeg_audio.cpp'),str(ROOT/'native/tests/NativeCustom.cpp'),str(ROOT/'build/aot/libFutariProgram.a'),'-lcompression','-o',str(exe)],check=True)
    for route in ROUTES:convert_replay(ROOT/'docs/evidence/replays'/f'{ROUTES[route]}.lua',out/f'{route}.inputs.tsv')
    tasks=[]
    if 'routes' in args.checks:tasks.extend((route,route,'standard') for route in ROUTES)
    for mode in ['combined','endless','campaign']:
        if mode in args.checks:tasks.append((mode,'reco-normal',mode))
    def run(task):
        name,route,mode=task;prefix=out/name
        if prefix.with_suffix('.settings').exists():raise RuntimeError('Use a fresh verification directory')
        command=[str(exe),str(resources),str(out/f'{route}.inputs.tsv'),str(prefix),mode]
        with prefix.with_suffix('.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
        lines=prefix.with_suffix('.log').read_text().splitlines()
        print(f'{name}: passed',flush=True)
        return {'name':name,'mode':mode,'route':route,'passed':True,'checks':[s for s in lines if s.startswith('PASS')],
                'input_sha256':hashlib.sha256((out/f'{route}.inputs.tsv').read_bytes()).hexdigest()}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,min(2,args.jobs))) as pool:results=list(pool.map(run,tasks))
    report={'native':True,'headless':True,'mame_runtime':False,'core':results}
    if 'menu' in args.checks:
        with (out/'menu.log').open('w') as log:
            subprocess.run([str(args.app.resolve()/'Contents/MacOS/Futari'),'--verify-menu',str(out/'reco-normal.inputs.tsv'),str(out/'menu')],stdout=log,stderr=subprocess.STDOUT,check=True)
        report['menu']=json.loads((out/'menu/verification.json').read_text());print('offscreen menu: passed',flush=True)
    (out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
