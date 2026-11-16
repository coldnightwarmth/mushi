#!/usr/bin/env python3
"""Build a local macOS launcher for the original-game reference runtime."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shlex
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
    command = [str(binary), "futari15", "-rompath", str(rom.parent), "-window", "-resolution", "720x960", "-nofilter", "-keepaspect", "-sound", "sdl", "-skip_gameinfo",
               "-cfg_directory", str(cfg), "-nvram_directory", str(state / "nvram"), "-snapshot_directory", str(state / "snap")]
    script = "#!/bin/zsh\nset -eu\n"
    if args.frameworks:
        script += "export DYLD_FRAMEWORK_PATH=" + shlex.quote(str(args.frameworks.resolve())) + "\n"
    script += "cd " + shlex.quote(str(ROOT)) + "\nexec " + shlex.join(command) + ' "$@" >> ' + shlex.quote(str(state / "app.log")) + " 2>&1\n"
    exe.write_text(script);exe.chmod(0o755)
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump(dict(CFBundleName="Futari 1.5 Reference",CFBundleDisplayName="Futari 1.5 Reference",CFBundleExecutable=exe.name,
                          CFBundleIdentifier="local.mushi.reference",CFBundlePackageType="APPL",CFBundleVersion="1",NSHighResolutionCapable=True),stream)
    (resources / "runtime.json").write_text(json.dumps(dict(kind="MAME reference launcher; not native decompiled gameplay",mame=str(binary),rom=str(rom),command=command),indent=2)+"\n")
    print(app)


if __name__ == "__main__":
    main()
