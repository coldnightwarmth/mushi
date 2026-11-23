#!/usr/bin/env python3
"""Incremental ahead-of-time compilation; never executed by the game host."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
generated=ROOT/'build/aot/generated'
objects=ROOT/'build/aot/objects';objects.mkdir(parents=True,exist_ok=True)
sources=json.loads((generated/'manifest.json').read_text())['sources']
header=ROOT/'native/core/CompiledState.hpp'
recovered=ROOT/'native/core/RecoveredDrawQueue.hpp'
def compile(name):
    src=generated/name;obj=objects/(src.stem+'.o')
    dependency=max(src.stat().st_mtime,header.stat().st_mtime,
                   recovered.stat().st_mtime if name=='dispatch.cpp' else 0)
    if obj.exists() and obj.stat().st_mtime>dependency: return False
    result=subprocess.run(['xcrun','clang++','-std=c++17','-O1','-Wno-tautological-compare','-I',str(header.parent),'-c',str(src),'-o',str(obj)],capture_output=True,text=True)
    if result.returncode: raise RuntimeError(name+'\n'+result.stderr[-6000:])
    return True
start=time.monotonic();done=0
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for rebuilt in pool.map(compile,sources):
        done+=1
        if done%20==0: print(f'{done}/{len(sources)} native units ({time.monotonic()-start:.0f}s)',flush=True)
subprocess.run(['xcrun','ar','rcs',str(ROOT/'build/aot/libFutariProgram.a')]+[str(objects/(Path(n).stem+'.o')) for n in sources],check=True)
print(f'Native program archive ready ({time.monotonic()-start:.1f}s)',flush=True)
