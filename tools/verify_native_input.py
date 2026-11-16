#!/usr/bin/env python3
"""Differentially verify native Swift input services against original instructions."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mushi.rom import load_roms, swap_words
from mushi.compression import decompress
from mushi.reference import HEADLESS_OPTIONS, headless_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--mame", type=Path, required=True)
    parser.add_argument("--frameworks", type=Path)
    args = parser.parse_args()
    roms, _ = load_roms(args.rom)
    program = swap_words(roms["futari15_u4"])
    program = program[:0x51000] + decompress(program[0x51000:]).data
    out = ROOT / "build/native-input"
    out.mkdir(parents=True, exist_ok=True)
    (out / "program.bin").write_bytes(program)
    randomizer = random.Random(154)
    cases = []
    def add(entry, words, argument=0):
        cases.append(struct.pack(">II34I", entry, argument, *words))
    for fill in [0, 1, 0xffffffff, 0xa5a5a5a5]:
        add(0x0c05c4f0, [fill] * 34)
    masks = [1, 2, 4, 8, 16, 32, 64, 128, 0x8000]
    timers = [0, 1, 2, 4, 16, 0xffffffff, 0xfffffffe, 0x80000000]
    for pattern in range(512):
        words = [randomizer.getrandbits(32) for _ in range(34)]
        for player in range(2):
            base = player * 17
            bits = pattern if player == 0 else pattern ^ 511
            words[base + 3] = sum(mask for i, mask in enumerate(masks) if bits & (1 << i))
            words[base + 6] = [0, 1, 16, 0xffffffff][pattern % 4]
            words[base + 7] = [0, 1, 4, 0xffffffff][(pattern // 4) % 4]
            for i in range(9):
                words[base + 8 + i] = timers[(pattern + i + player) % len(timers)]
        add(0x0c05c62c, words)
    for _ in range(128):
        words = [randomizer.getrandbits(32) for _ in range(34)]
        add(0x0c05c62c, words)
        for entry in [0x0c05ca18, 0x0c05ca30, 0x0c05ca48, 0x0c05caa0]:
            for selector in [0, 1, 2, 0xffffffff]:
                add(entry, words, selector)
    for value in [0, 1, 0xfffffffe, 0xffffffff]:
        words = [value] * 34
        add(0x0c05caa0, words, 0)
        add(0x0c05caa0, words, 1)
    snapshots = sorted(ROOT.glob("build/*/ram-*.bin"))
    for snapshot in snapshots:
        with snapshot.open("rb") as file:
            file.seek(0x5c468)
            records = file.read(0x88)
        if len(records) == 0x88:
            add(0x0c05c62c, struct.unpack(">34I", records))
    (out / "inputs.bin").write_bytes(b"".join(cases))
    env = headless_environment(args.frameworks)
    env["MUSHI_INPUT_TEST"] = str(out)
    command = [str(args.mame.resolve()), "futari15", "-rompath", str(args.rom.resolve().parent),
               *HEADLESS_OPTIONS, "-verbose", "-nothrottle", "-nodrc", "-skip_gameinfo",
               "-autoboot_delay", "0", "-autoboot_script", str(ROOT / "tools/verify_input.lua"),
               "-cfg_directory", str(out / "cfg"), "-nvram_directory", str(out / "nvram"),
               "-seconds_to_run", str(len(cases) // 50 + 30)]
    with (out / "oracle.log").open("w") as log:
        subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=240)
    expected_size = len(cases) * (0x88 + 4)
    actual_size = (out / "original-output.bin").stat().st_size
    if actual_size != expected_size:
        raise RuntimeError(f"Reference run ended early: {actual_size // 140} / {len(cases)} cases; see {out / 'oracle.log'}")
    executable = out / "VerifyInput"
    subprocess.run(["xcrun", "swiftc", "-O", "-warnings-as-errors",
                    str(ROOT / "native/core/InputState.swift"),
                    str(ROOT / "native/core/FutariInputPorts.swift"),
                    str(ROOT / "native/platform/ArcadeButtons.swift"),
                    str(ROOT / "native/platform/MacControls.swift"),
                    str(ROOT / "native/tests/InputVerification.swift"),
                    "-o", str(executable)], check=True)
    result = subprocess.run([str(executable), str(out / "inputs.bin"), str(out / "original-output.bin")],
                            text=True, capture_output=True)
    if result.returncode:
        print(result.stdout + result.stderr, file=sys.stderr)
        result.check_returncode()
    print(result.stdout, end="")
    report = dict(entries=["0x0c05c4f0", "0x0c05c62c", "0x0c05ca18", "0x0c05ca30", "0x0c05ca48", "0x0c05caa0"],
                  cases=len(cases), captured_states=len(snapshots), record_bytes=0x88,
                  state_byte_exact=True, query_returns_exact=True, keyboard_checks_pass=True,
                  oracle="Original SH-3 instructions under MAME; test only",
                  native="Swift compiled for macOS; no emulator dependency",
                  reference_video_driver="dummy", reference_audio_driver="dummy",
                  inputs_sha256=hashlib.sha256((out / "inputs.bin").read_bytes()).hexdigest(),
                  original_sha256=hashlib.sha256((out / "original-output.bin").read_bytes()).hexdigest())
    (out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
