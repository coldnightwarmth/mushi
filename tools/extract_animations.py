#!/usr/bin/env python3
"""Verify and export reviewed original animation tracks."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from mushi.animation_catalog import export

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--catalog',type=Path,default=ROOT/'build/catalog')
    a=p.parse_args();out=ROOT/'build/animation-verified'
    subprocess.run([sys.executable,str(ROOT/'tools/verify_recovered.py'),'--checks',
                    'effects','random','particles','particle-init','particle-sequences','--output',str(out)],check=True)
    report=export(out/'effect-sequence.tsv',a.catalog,out/'particle-sequence.tsv')
    report['native_checks']=json.loads((out/'verification.json').read_text())['checks']
    (ROOT/'docs/evidence/animation-extraction.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
