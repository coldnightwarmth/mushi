#!/usr/bin/env python3
"""Headless native route replay. No emulator, windows or audio device involved."""
import argparse,concurrent.futures,hashlib,json,re,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ROUTES={'reco-normal':'stage-clear','reco-abnormal':'reco-abnormal-clear',
        'palm-normal':'palm-normal-clear','palm-abnormal':'palm-abnormal-clear'}
MASKS={'Coin 1':4,'1 Player Start':16,'P1 Button 1':16,'P1 Button 2':32,'P1 Button 3':64,
       'P1 Up':1,'P1 Down':2,'P1 Left':4,'P1 Right':8}

def convert_replay(source,destination):
    c=d=255;events={}
    for frame,port,key,value in re.findall(r'\{(\d+), ":PORT_([CD])", "([^"]+)", (\d+)\}',source.read_text()):
        mask=MASKS[key]
        if port=='C':c=c&~mask if int(value) else c|mask
        else:d=d&~mask if int(value) else d|mask
        events[int(frame)]=(c,d)
    destination.write_text(''.join(f'{f} {c} {d}\n' for f,(c,d) in sorted(events.items())))

def main():
    p=argparse.ArgumentParser();p.add_argument('--resources',type=Path,default=ROOT/'build/aot/resources')
    p.add_argument('--output',type=Path,default=ROOT/'build/native-routes');p.add_argument('--jobs',type=int,default=1)
    p.add_argument('--route',choices=list(ROUTES)+['all'],default='all');a=p.parse_args()
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    exe=out/'NativeBoot'
    sources=['native/core/Board.cpp','native/core/Graphics.cpp','native/core/Audio.cpp','native/vendor/mpeg_audio.cpp','native/tests/NativeBoot.cpp']
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-I',str(ROOT/'native/core'),*[str(ROOT/s) for s in sources],str(ROOT/'build/aot/libFutariProgram.a'),'-o',str(exe)],check=True)
    routes=list(ROUTES) if a.route=='all' else [a.route]
    def run(route):
        name=ROUTES[route];prefix=out/name;events=prefix.with_suffix('.tsv')
        convert_replay(ROOT/'docs/evidence/replays'/f'{name}.lua',events)
        with prefix.with_suffix('.log').open('w') as log:
            subprocess.run([str(exe),str(a.resources.resolve()),'15000',str(prefix),str(events)],stdout=log,stderr=subprocess.STDOUT,check=True)
        ram=prefix.with_suffix('.ram').read_bytes();stage=struct.unpack_from('>H',ram,0x38a586)[0]
        if stage!=1:raise RuntimeError(f'{route}: expected stage two after replay, got index {stage}')
        return dict(route=route,frames=15000,final_stage_index=stage,input_sha256=hashlib.sha256(events.read_bytes()).hexdigest())
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,min(2,a.jobs))) as pool:results=list(pool.map(run,routes))
    (out/'verification.json').write_text(json.dumps(dict(native=True,cpu_interpreter=False,routes=results),indent=2)+'\n')
    print(json.dumps(results,indent=2))
if __name__=='__main__':main()
