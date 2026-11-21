#!/usr/bin/env python3
"""Build the native ARM64 Futari app from the user's verified game data."""
import argparse,hashlib,json,os,plistlib,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from mushi.rom import load_roms,swap_words
from mushi.compression import decompress

def main():
    p=argparse.ArgumentParser();p.add_argument('--rom',type=Path,required=True);p.add_argument('--output',type=Path,default=ROOT/'build/macos/Mushihimesama Futari.app');p.add_argument('--skip-program',action='store_true');a=p.parse_args()
    os.chdir(ROOT)
    roms,verification=load_roms(a.rom)
    resources=ROOT/'build/aot/resources';resources.mkdir(parents=True,exist_ok=True)
    program=swap_words(roms['futari15_u4']);expanded=program[:0x51000]+decompress(program[0x51000:]).data
    for name,data in [('u4-be.bin',program),('expanded.bin',expanded),('nand.bin',roms['futari15_u2']),('sound.bin',swap_words(roms['u23']+roms['u24']))]:
        path=resources/name
        if not path.exists() or path.read_bytes()!=data:path.write_bytes(data)
    if not a.skip_program:
        subprocess.run([sys.executable,'tools/recompile_program.py','--program',str(resources/'expanded.bin')],check=True)
        subprocess.run([sys.executable,'tools/build_aot.py'],check=True)
    manifest=json.loads((ROOT/'build/aot/generated/manifest.json').read_text())
    if manifest['program_sha256']!=hashlib.sha256(expanded).hexdigest():
        raise RuntimeError('Compiled program does not match the verified ROM; rebuild without --skip-program')
    if manifest.get('translator_sha256')!=hashlib.sha256((ROOT/'tools/recompile_program.py').read_bytes()).hexdigest():
        raise RuntimeError('Compiled program predates the current translator; rebuild without --skip-program')
    objects=ROOT/'build/aot/host';objects.mkdir(parents=True,exist_ok=True)
    sources=['native/core/Board.cpp','native/core/Graphics.cpp','native/core/Audio.cpp','native/core/NativeGame.cpp','native/core/NativePresentation.cpp','native/vendor/mpeg_audio.cpp']
    compiled=[]
    for source in sources:
        obj=objects/(Path(source).stem+'.o');compiled.append(str(obj))
        subprocess.run(['xcrun','clang++','-std=c++17','-O2','-I','native/core','-c',source,'-o',str(obj)],check=True)
    app=a.output.resolve();contents=app/'Contents';macos=contents/'MacOS';bundled=contents/'Resources'
    macos.mkdir(parents=True,exist_ok=True);bundled.mkdir(exist_ok=True)
    exe=macos/'Futari'
    swift=['native/platform/ArcadeButtons.swift','native/platform/MacControls.swift','native/core/FutariInputPorts.swift','native/platform/FutariApplication.swift','native/platform/FutariMenu.swift','native/platform/FutariVisuals.swift','native/platform/FutariTrails.swift','native/tests/MenuVerification.swift','native/shared/MetaMenuModel.swift','native/shared/ArtEffectOptions.swift','native/shared/ArtEffects.swift','native/shared/ArtMemory.swift','native/shared/RetroMenuFont.swift']
    subprocess.run(['xcrun','swiftc','-O','-import-objc-header','native/core/NativeGame.h','-framework','AppKit','-framework','AVFoundation',*swift,*compiled,'build/aot/libFutariProgram.a','-lc++','-lcompression','-o',str(exe)],check=True)
    for name in ['u4-be.bin','expanded.bin','nand.bin','sound.bin']:shutil.copy2(resources/name,bundled/name)
    shutil.copy2(ROOT/'native/THIRD_PARTY_NOTICES.md',bundled/'THIRD_PARTY_NOTICES.md')
    (bundled/'runtime.json').write_text(json.dumps(dict(kind='Ahead-of-time native game code and native board services',architecture='arm64',cpu_interpreter=False,jit=False,mame_runtime=False,program=manifest,roms=verification),indent=2)+'\n')
    with (contents/'Info.plist').open('wb') as f:
        plistlib.dump(dict(CFBundleName='Mushihimesama Futari',CFBundleDisplayName='Mushihimesama Futari',CFBundleExecutable='Futari',CFBundleIdentifier='local.mushi.native',CFBundlePackageType='APPL',CFBundleVersion='3',CFBundleShortVersionString='0.4.0',NSHighResolutionCapable=True,LSMinimumSystemVersion='13.0'),f)
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    print(app)
if __name__=='__main__':main()
