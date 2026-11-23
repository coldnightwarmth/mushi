#!/usr/bin/env python3
"""Extract every sound-directory phrase without opening a window/audio device."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from mushi.rom import load_roms,swap_words
from mushi.audio_catalog import export

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rom',type=Path,required=True)
    p.add_argument('--catalog',type=Path,default=ROOT/'build/catalog')
    a=p.parse_args();roms,_=load_roms(a.rom)
    sound=swap_words(roms['u23']+roms['u24'])
    out=ROOT/'build/audio-extracted';out.mkdir(parents=True,exist_ok=True)
    bank=out/'sound.bin';bank.write_bytes(sound)
    exe=out/'ExtractAudio'
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-I',str(ROOT/'native/core'),
                    str(ROOT/'native/tests/ExtractAudio.cpp'),str(ROOT/'native/core/Audio.cpp'),str(ROOT/'native/vendor/mpeg_audio.cpp'),'-o',str(exe)],check=True)
    subprocess.run([str(exe),str(bank),str(out)],check=True)
    report=export(sound,out,a.catalog)
    (ROOT/'docs/evidence/audio-extraction.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
