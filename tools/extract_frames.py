#!/usr/bin/env python3
"""Verify and export the original frame directory without opening a game window."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from mushi.frame_catalog import export

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog',type=Path,default=ROOT/'build/catalog')
    parser.add_argument('--resources',type=Path,default=ROOT/'build/aot/resources')
    args=parser.parse_args()
    exe=ROOT/'build/verify-sprite-frames'
    codec=ROOT/'build/frame-verification-codec.o'
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-c',
                    str(ROOT/'native/vendor/mpeg_audio.cpp'),'-o',str(codec)],check=True)
    # Compile from source so verification cannot silently use stale host objects.
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-Wall','-Wextra','-Werror',
                    '-I',str(ROOT/'native/core'),str(ROOT/'native/tests/RecoveredSpriteFrames.cpp'),
                    *[str(ROOT/'native/core'/name) for name in ('Board.cpp','Graphics.cpp','Audio.cpp')],
                    str(codec),str(ROOT/'build/aot/libFutariProgram.a'),
                    '-o',str(exe)],check=True)
    program=args.resources/'expanded.bin'
    verified=subprocess.run([str(exe),str(program),str(args.resources)],check=True,text=True,capture_output=True)
    print(verified.stdout,flush=True)
    report=export(program.read_bytes(),args.catalog)
    report['native_checks']=verified.stdout.splitlines()
    (ROOT/'docs/evidence/frame-extraction.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
