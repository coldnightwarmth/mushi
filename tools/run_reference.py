#!/usr/bin/env python3
"""Launch or capture the original game as a separately identified MAME reference."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mushi.rom import load_roms
from mushi.reference import HEADLESS_OPTIONS, headless_environment


def arguments():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mame", type=Path, required=True)
    p.add_argument("--frameworks", type=Path)
    p.add_argument("--rom", type=Path, required=True)
    p.add_argument("--capture", type=Path)
    p.add_argument("--frames", type=int, default=4800)
    p.add_argument("--snapshots", default="2450,2800,3000,3150,3400,4000,4800")
    p.add_argument("--character", choices=("reco", "palm"), default="reco")
    p.add_argument("--shot", choices=("normal", "abnormal"), default="normal")
    p.add_argument("--autoplay", action="store_true", help="Fire, bomb, insert credits and continue; no RAM cheats")
    p.add_argument("--graphics", action="store_true", help="Capture full VRAM at snapshot frames")
    p.add_argument("--audio", action="store_true", help="Capture reference audio to WAV")
    return p.parse_args()


def make_replay(character, shot, frames, autoplay):
    events = []
    def press(frame, port, button, duration=12):
        events.extend([(frame, port, button, 1), (frame + duration, port, button, 0)])
    press(2400, ":PORT_C", "Coin 1")
    press(2500, ":PORT_C", "1 Player Start")
    press(2700, ":PORT_D", "P1 Button 1")
    if character == "palm":
        press(2820, ":PORT_D", "P1 Right")
    press(2900, ":PORT_D", "P1 Button 1")
    if shot == "abnormal":
        press(3020, ":PORT_D", "P1 Down")
    press(3100, ":PORT_D", "P1 Button 1")
    events.append((3300, ":PORT_D", "P1 Button 3", 1))
    if autoplay:
        for frame in range(3700, frames - 12, 180):
            press(frame, ":PORT_C", "Coin 1")
            press(frame + 30, ":PORT_C", "1 Player Start")
        for frame in range(3500, frames - 12, 240):
            press(frame, ":PORT_D", "P1 Button 2")
    return "return {\n" + "".join("    {%d, %s, %s, %d},\n" % (f, json.dumps(p), json.dumps(b), v) for f,p,b,v in sorted(events)) + "}\n"


def main():
    args = arguments()
    rom, binary = args.rom.resolve(), args.mame.resolve()
    _, manifest = load_roms(rom)
    if rom.name != "futari15.zip":
        raise SystemExit("MAME reference currently requires archive filename futari15.zip")
    env = headless_environment(args.frameworks) if args.capture else os.environ.copy()
    if args.frameworks:
        env["DYLD_FRAMEWORK_PATH"] = str(args.frameworks.resolve())
    state = (args.capture or ROOT / "build/reference").resolve()
    state.mkdir(parents=True, exist_ok=True)
    command = [str(binary), "futari15", "-rompath", str(rom.parent), "-skip_gameinfo",
               "-cfg_directory", str(state / "cfg"), "-nvram_directory", str(state / "nvram"),
               "-snapshot_directory", str(state / "snap")]
    if args.capture:
        replay = state / "replay.lua"
        replay.write_text(make_replay(args.character, args.shot, args.frames, args.autoplay))
        env.update(MUSHI_CAPTURE=str(state), MUSHI_FRAMES=str(args.frames),
                   MUSHI_SNAPSHOTS=args.snapshots, MUSHI_REPLAY=str(replay),
                   MUSHI_GFX="1" if args.graphics else "0")
        command += [*HEADLESS_OPTIONS, "-nothrottle", "-seconds_to_run", str(args.frames // 59 + 10),
                    "-autoboot_delay", "0", "-autoboot_script", str(ROOT / "tools/probe.lua")]
        if args.audio:
            command += ["-wavwrite", str(state / "audio.wav")]
    else:
        command += ["-window", "-resolution", "720x960", "-nofilter", "-keepaspect", "-sound", "sdl"]
    version = subprocess.run([str(binary), "-help"], env=env, capture_output=True, text=True, check=True).stdout.splitlines()[0]
    (state / "run.json").write_text(json.dumps(dict(runtime="MAME reference, not native decompiled gameplay", version=version,
        character=args.character, shot=args.shot, mode="Original", frames=args.frames if args.capture else None,
        autoplay=args.autoplay, headless=bool(args.capture),
        video_driver=env.get("SDL_VIDEO_DRIVER") if args.capture else "interactive",
        command=command, rom=manifest), indent=2) + "\n")
    with (state / "run.log").open("w") as log:
        subprocess.run(command, env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    print(state)


if __name__ == "__main__":
    main()
