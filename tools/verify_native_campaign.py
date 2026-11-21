#!/usr/bin/env python3
"""Native full-game replays, restart verification and exact resource observation."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from verify_native_playthroughs import ROUTES,convert_replay

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--route',choices=list(ROUTES)+['all'],default='all')
    p.add_argument('--output',type=Path,default=ROOT/'build/native-campaign-verified')
    p.add_argument('--resources',type=Path,default=ROOT/'build/aot/resources')
    p.add_argument('--catalog',type=Path,default=ROOT/'build/catalog')
    p.add_argument('--jobs',type=int,default=1)
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    import numpy as np
    from PIL import Image
    from mushi.observations import argb_to_vram
    from mushi.catalog import read_manifest
    manifest=read_manifest(a.catalog)
    hashes=out/'resource-hashes.tsv'
    with hashes.open('w') as h:
        for record in manifest['resources']:
            with Image.open(a.catalog/record['source']) as im:
                digest=hashlib.sha256(argb_to_vram(np.asarray(im)).tobytes()).hexdigest()
            h.write(f"{record['index']} {digest}\n")
    exe=out/'NativeCampaign'
    sources=['native/core/Board.cpp','native/core/Graphics.cpp','native/core/Audio.cpp','native/core/NativeGame.cpp','native/core/NativePresentation.cpp',
             'native/vendor/mpeg_audio.cpp','native/tests/NativeCampaign.cpp']
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-Wno-deprecated-declarations','-I',str(ROOT/'native/core'),
                    *[str(ROOT/s) for s in sources],str(ROOT/'build/aot/libFutariProgram.a'),'-lcompression','-o',str(exe)],check=True)
    def run(route):
        prefix=out/route;events=prefix.with_suffix('.menu.tsv')
        convert_replay(ROOT/'docs/evidence/replays'/f'{ROUTES[route]}.lua',events)
        events.write_text(''.join(line+'\n' for line in events.read_text().splitlines() if int(line.split()[0])<3300))
        if prefix.with_suffix('.settings.bin').exists():
            raise RuntimeError(f'{prefix}: use a fresh output directory to start with factory settings')
        metadata=dict(route=route,mode='Original',character=route.split('-')[0].title(),shot=route.split('-')[1].title(),
                      native=True,ordinary_damage=True,paid_continues=True,ram_cheats=False)
        prefix.with_suffix('.run.json').write_text(json.dumps(metadata,indent=2)+'\n')
        with prefix.with_suffix('.log').open('w') as log:
            subprocess.run([str(exe),str(a.resources.resolve()),str(events),str(prefix),str(hashes)],stdout=log,stderr=subprocess.STDOUT,check=True)
        result=json.loads(prefix.with_suffix('.verification.json').read_text());result.update(metadata)
        result['input_sha256']=hashlib.sha256(prefix.with_suffix('.inputs.tsv').read_bytes()).hexdigest()
        prefix.with_suffix('.verification.json').write_text(json.dumps(result,indent=2)+'\n')
        print(f"{route}: all five stages and ending passed ({result['attract_frame']+1} frames)",flush=True)
        return result
    routes=list(ROUTES) if a.route=='all' else [a.route]
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,min(2,a.jobs))) as pool:results=list(pool.map(run,routes))
    (out/'verification.json').write_text(json.dumps(dict(native=True,cpu_interpreter=False,routes=results),indent=2)+'\n')

if __name__=='__main__':main()
