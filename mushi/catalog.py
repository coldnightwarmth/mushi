"""Exhaustive resource export, with provenance separate from semantic coverage."""
from collections import Counter
from dataclasses import asdict
from hashlib import sha256
from pathlib import Path
import json
import shutil
from PIL import Image, ImageDraw
from .compression import decompress
from .rom import load_roms, swap_words
from .nand import Nand
from .graphics import decode_bitmap


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def build(rom_path: Path, output: Path):
    roms, rom_manifest = load_roms(rom_path)
    nand = Nand(roms["futari15_u2"])
    output.mkdir(parents=True, exist_ok=True)
    for name in ("sheets", "thumbs", "contact", "metadata"):
        (output / name).mkdir(exist_ok=True)
    records, hashes = [], {}
    for resource in nand.resources:
        data, spans, consumed = nand.decode(resource)
        image, info = decode_bitmap(data)
        stem = f"u2-{resource.index:04d}"
        image.save(output / "sheets" / f"{stem}.png")
        # Arcade board graphics are sideways; present upright previews while
        # preserving an unrotated source image for exact byte/coordinate tracing.
        upright = image.transpose(Image.Transpose.ROTATE_90)
        upright.thumbnail((160, 160), Image.Resampling.NEAREST)
        upright.save(output / "thumbs" / f"{stem}.png")
        digest = sha256(data).hexdigest()
        alias = hashes.get(digest)
        hashes.setdefault(digest, resource.index)
        record = dict(id=stem, **asdict(resource), **info, spans=spans,
                      decoded_bytes=len(data), compressed_consumed=consumed,
                      sha256=digest, duplicate_of=alias,
                      source=f"sheets/{stem}.png", thumbnail=f"thumbs/{stem}.png",
                      status="decoded-resource", classification="unclassified",
                      note="Resource sheet; individual frames and animation timing are not yet established.")
        records.append(record)
        write_json(output / "metadata" / f"{stem}.json", record)
        if len(records) % 100 == 0:
            print(f"Decoded {len(records)} / {len(nand.resources)} resources", flush=True)
    # Contact sheets are an inspection aid, not inferred animation sequences.
    for start in range(0, len(records), 100):
        page = records[start:start + 100]
        sheet = Image.new("RGB", (1000, 1100), "#171c1a")
        draw = ImageDraw.Draw(sheet)
        for i, rec in enumerate(page):
            with Image.open(output / rec["thumbnail"]) as preview:
                preview.thumbnail((92, 92), Image.Resampling.NEAREST)
                x, y = (i % 10) * 100 + 4, (i // 10) * 110 + 3
                sheet.paste(preview, (x, y), preview)
                draw.text((x, y + 94), rec["id"], fill="#e1e8ce")
        sheet.save(output / "contact" / f"{start:04d}-{start+len(page)-1:04d}.png")
    program_dir = output.parent / "program"
    program_dir.mkdir(exist_ok=True)
    program = swap_words(roms["futari15_u4"])
    payload = decompress(program[0x51000:])
    (program_dir / "u4-be.bin").write_bytes(program)
    (program_dir / "payload.bin").write_bytes(payload.data)
    (program_dir / "expanded.bin").write_bytes(program[:0x51000] + payload.data)
    program_info = dict(source="futari15_u4", compression_offset=0x51000,
                        decoded_bytes=len(payload.data), consumed_bytes=payload.consumed,
                        operations=payload.operations, sha256=sha256(payload.data).hexdigest(),
                        runtime_payload_address="0x0c051000",
                        address_evidence="Confirmed against live MAME RAM; mutable data differs after startup.")
    coverage = dict(resource_entries=len(records), decoded_resources=len(records),
                    unique_payloads=len(hashes), duplicate_payloads=len(records)-len(hashes),
                    compressed_resources=sum(bool(r.compression) for r in nand.resources),
                    raw_resources=sum(not r.compression for r in nand.resources),
                    decoded_bytes=sum(r["decoded_bytes"] for r in records),
                    opaque_pixels=sum(r["opaque_pixels"] for r in records),
                    bad_blocks=sorted(nand.bad_blocks),
                    verified_sprite_families=0, verified_animation_sequences=0,
                    native_gameplay_complete=False,
                    scope="All directory-listed bitmap resources are decoded. This is not yet a comprehensive semantic sprite/animation catalog.")
    manifest = dict(schema=1, game="Mushihimesama Futari 1.5", rom=rom_manifest,
                    coverage=coverage, program=program_info, resources=records)
    write_json(output / "catalog.json", manifest)
    write_json(output / "coverage.json", coverage)
    write_json(program_dir / "program.json", program_info)
    # Static data script allows offline browsing from file:// as well as HTTP.
    (output / "catalog-data.js").write_text("window.MUSHI_CATALOG=" + json.dumps(manifest, separators=(",", ":")) + ";\n")
    web = Path(__file__).parent / "web"
    for name in ("index.html", "catalog.css", "catalog.js"):
        shutil.copyfile(web / name, output / name)
    print(json.dumps(coverage, indent=2))
    print(output / "index.html")
    return manifest
