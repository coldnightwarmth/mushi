#!/usr/bin/env python3
"""Import expanded SH3 code into Ghidra and export explicitly unreviewed analysis."""
import argparse
from pathlib import Path
import os
import subprocess

ROOT=Path(__file__).resolve().parents[1]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ghidra',type=Path,required=True);p.add_argument('--java-home',type=Path,required=True)
    args=p.parse_args()
    program=ROOT/'build/program/expanded.bin'
    if not program.exists():raise SystemExit('Build the catalog first to generate the expanded program')
    out=ROOT/'build/ghidra';out.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy();env['JAVA_HOME']=str(args.java_home.resolve())
    command=[str(args.ghidra.resolve()/'support/analyzeHeadless'),str(out),'Futari','-import',str(program),'-overwrite',
             '-processor','SuperH4:BE:32:default','-loader','BinaryLoader','-loader-baseAddr','0x0c000000',
             '-scriptPath',str(ROOT/'tools/ghidra'),'-preScript','SeedFutari.java',
             '-postScript','ExportFutari.java',str(ROOT/'build/analysis'),'-analysisTimeoutPerFile','600','-max-cpu','4']
    with (ROOT/'build/ghidra.log').open('w') as log:subprocess.run(command,env=env,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    log_text=(ROOT/'build/ghidra.log').read_text()
    if 'Analysis timed out' in log_text:raise SystemExit('Ghidra analysis timed out; exported results are partial')
    if 'SCRIPT ERROR' in log_text or 'error:' in log_text:raise SystemExit('Ghidra script failed; see build/ghidra.log')
    print(ROOT/'build/analysis')


if __name__=='__main__':main()
