#!/usr/bin/env python3
"""Compare reviewed services with the original AOT implementation, headlessly."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from verify_native_playthroughs import ROUTES, convert_replay

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,default=ROOT/'build/recovered-verified')
    p.add_argument('--checks',nargs='+',choices=['queue','drain','effects','campaign'],default=['queue','drain','effects'])
    p.add_argument('--route',choices=list(ROUTES),default='reco-normal')
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    resources=ROOT/'build/aot/resources';generated=ROOT/'build/aot/generated'
    manifest=json.loads((generated/'manifest.json').read_text())
    if manifest['translator_sha256']!=hashlib.sha256((ROOT/'tools/recompile_program.py').read_bytes()).hexdigest():
        raise RuntimeError('Rebuild the native AOT program before running recovered-service checks')
    baseline=out/'original-dispatch.o'
    subprocess.run(['xcrun','clang++','-std=c++17','-O1','-DFUTARI_ORIGINAL_DISPATCH',
                    '-I',str(ROOT/'native/core'),'-c',str(generated/'dispatch.cpp'),'-o',str(baseline)],check=True)
    report=dict(program_sha256=manifest['program_sha256'],translator_sha256=manifest['translator_sha256'],
                oracle='Original AOT dispatcher, recovered service bypassed; not an independent hardware oracle',checks=[])
    for check in a.checks:
        name={'queue':'RecoveredDrawQueue','drain':'RecoveredDrawQueueDrain','effects':'RecoveredEffectSequence','campaign':'RecoveredReplay'}[check]
        exe=out/name;extra=[]
        if check=='campaign':
            codec=out/'codec.o'
            subprocess.run(['xcrun','clang++','-std=c++17','-O2','-c',str(ROOT/'native/vendor/mpeg_audio.cpp'),'-o',str(codec)],check=True)
            extra=[*[str(ROOT/'native/core'/n) for n in ('Board.cpp','Graphics.cpp','Audio.cpp')],str(codec)]
        subprocess.run(['xcrun','clang++','-std=c++17','-O2','-Wall','-Wextra','-Werror','-I',str(ROOT/'native/core'),
                        str(ROOT/'native/tests'/f'{name}.cpp'),*extra,str(baseline),str(ROOT/'build/aot/libFutariProgram.a'),'-o',str(exe)],check=True)
        args=[str(resources/'expanded.bin')]
        if check=='effects':args.append(str(out/'effect-sequence.tsv'))
        if check=='campaign':
            replay=out/f'{a.route}.inputs.tsv';convert_replay(ROOT/'docs/evidence/replays'/f'{ROUTES[a.route]}.lua',replay)
            args=[str(resources),str(replay)]
        log=out/f'{check}.log'
        with log.open('w') as stream:subprocess.run([str(exe),*args],stdout=stream,stderr=subprocess.STDOUT,check=True)
        passed=[s for s in log.read_text().splitlines() if s.startswith('PASS')]
        if not passed:raise RuntimeError(f'No completion evidence for {check}')
        report['checks'].append(dict(name=check,result=passed));print('\n'.join(passed),flush=True)
        (out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
