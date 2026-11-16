#!/usr/bin/env python3
"""Build a self-contained local macOS app for the original-game reference runtime."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mushi.rom import load_roms


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mame", required=True, type=Path)
    p.add_argument("--frameworks", type=Path)
    p.add_argument("--rom", required=True, type=Path)
    p.add_argument("--output", type=Path, default=ROOT / "build/macos/Futari 1.5 Reference.app")
    args = p.parse_args()
    rom = args.rom.resolve();binary = args.mame.resolve()
    load_roms(rom)
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise SystemExit("--mame must be an executable MAME binary")
    if rom.name != "futari15.zip":
        raise SystemExit("MAME requires the archive filename futari15.zip")
    app = args.output.resolve();contents = app / "Contents"
    resources = contents / "Resources";exe = contents / "MacOS/FutariReference"
    resources.mkdir(parents=True, exist_ok=True);exe.parent.mkdir(exist_ok=True)
    frameworks = contents / "Frameworks"
    frameworks.mkdir(exist_ok=True)
    # Keep the runtime and ROM inside the app. Launching a shell script from
    # Documents can fail TCC checks before its log redirection even executes.
    # Bundled code/resources and Application Support saves avoid that path.
    runtime = exe.parent / "mame"
    shutil.copy2(binary, runtime)
    dependencies = subprocess.run(["otool", "-L", str(runtime)], check=True, text=True, capture_output=True).stdout
    if "@rpath/SDL3.framework/" in dependencies:
        candidates = []
        if args.frameworks:
            candidates.append(args.frameworks.resolve() / "SDL3.framework")
        candidates += [binary.parent / "SDL3.framework", binary.parent.parent / "frameworks/SDL3.framework",
                       Path("/Library/Frameworks/SDL3.framework"),
                       Path("/Library/Frameworks/SDL3.xcframework/macos-arm64_x86_64/SDL3.framework")]
        source = next((p for p in candidates if p.is_dir()), None)
        if source is None:
            raise SystemExit("SDL3.framework was not found. Supply its parent directory with --frameworks.")
        shutil.copytree(source, frameworks / "SDL3.framework", symlinks=True, dirs_exist_ok=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(frameworks / "SDL3.framework")], check=True)
        # Use a direct bundle-relative dependency, not the build machine's rpath.
        subprocess.run(["install_name_tool", "-change", "@rpath/SDL3.framework/Versions/A/SDL3",
                        "@executable_path/../Frameworks/SDL3.framework/Versions/A/SDL3", str(runtime)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(runtime)], check=True)
    bundled_roms = resources / "roms"
    bundled_roms.mkdir(exist_ok=True)
    shutil.copy2(rom, bundled_roms / rom.name)
    state = ROOT / "build/reference";cfg = state / "cfg";cfg.mkdir(parents=True, exist_ok=True)
    bindings = {"COIN1":"KEYCODE_5 OR KEYCODE_BACKSLASH", "START1":"KEYCODE_ENTER OR KEYCODE_1",
                "P1_JOYSTICK_UP":"KEYCODE_UP OR KEYCODE_W", "P1_JOYSTICK_DOWN":"KEYCODE_DOWN OR KEYCODE_S",
                "P1_JOYSTICK_LEFT":"KEYCODE_LEFT OR KEYCODE_A", "P1_JOYSTICK_RIGHT":"KEYCODE_RIGHT OR KEYCODE_D",
                "P1_BUTTON1":"KEYCODE_J OR KEYCODE_Z", "P1_BUTTON2":"KEYCODE_L OR KEYCODE_X",
                "P1_BUTTON3":"KEYCODE_K OR KEYCODE_C"}
    # Seed defaults once; preserve the user's subsequent MAME control settings.
    config = cfg / "default.cfg"
    if not config.exists():
        root=ET.Element("mameconfig",version="10");system=ET.SubElement(root,"system",name="default")
        inputs=ET.SubElement(system,"input")
        for name,seq in bindings.items():
            port=ET.SubElement(inputs,"port",type=name);ET.SubElement(port,"newseq",type="standard").text=seq
        ET.indent(root);ET.ElementTree(root).write(config,encoding="utf-8",xml_declaration=True)
    seeds = resources / "seed-state"
    for name in ("cfg", "nvram"):
        if (state / name).exists():
            shutil.copytree(state / name, seeds / name, dirs_exist_ok=True)
    subprocess.run(["xcrun", "swiftc", "-O", "-framework", "AppKit",
                    str(ROOT / "native/ReferenceLauncher.swift"), "-o", str(exe)], check=True)
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump(dict(CFBundleName="Futari 1.5 Reference",CFBundleDisplayName="Futari 1.5 Reference",CFBundleExecutable=exe.name,
                          CFBundleIdentifier="local.mushi.reference",CFBundlePackageType="APPL",CFBundleVersion="2",
                          CFBundleShortVersionString="0.1.1",NSHighResolutionCapable=True),stream)
    (resources / "runtime.json").write_text(json.dumps(dict(kind="MAME reference launcher; not native decompiled gameplay",
        mame="Contents/MacOS/mame",rom="Contents/Resources/roms/futari15.zip",
        state="~/Library/Application Support/Mushi/Reference",launcher="native Mach-O v2"),indent=2)+"\n")
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    print(app)


if __name__ == "__main__":
    main()
