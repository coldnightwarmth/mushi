"""Exhaustive resource export, with provenance separate from semantic coverage."""
from collections import Counter
from dataclasses import asdict
from hashlib import sha256
from pathlib import Path
import json
import gzip
import shutil
from PIL import Image, ImageDraw
from .compression import decompress
from .rom import load_roms, swap_words
from .nand import Nand
from .graphics import decode_bitmap


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def read_manifest(output):
    manifest=json.loads((output/'catalog.json').read_text())
    if manifest.get('full_manifest'):
        manifest=json.loads(gzip.decompress((output/manifest['full_manifest']).read_bytes()))
    return manifest


def write_manifest(output, manifest):
    encoded=(json.dumps(manifest,indent=2)+'\n').encode()
    (output/'catalog-full.json.gz').write_bytes(gzip.compress(encoded,compresslevel=6,mtime=0))
    if len(encoded)>64*1024*1024:
        # Keep every individual provenance file, and avoid a >100 MB Git blob.
        index={k:v for k,v in manifest.items() if k!='observed'}
        index['schema']=2;index['full_manifest']='catalog-full.json.gz'
        index['observed']=[{k:r[k] for k in ('id','resource_index','source_rect','metadata')} for r in manifest['observed']]
        write_json(output/'catalog.json',index)
    else:(output/'catalog.json').write_bytes(encoded)


def write_browser_data(output, manifest):
    """Compact the large rectangle index; complete evidence stays in JSON files."""
    observed=manifest.get('observed',[])
    contexts=[];context_ids={};rows=[];descriptions=[];description_ids={}
    for r in observed:
        evidence=r['observations'];ids=[]
        for o in evidence:
            context=(o['capture'],o['mode'],o['character'],o['shot'],o.get('runtime','reference'),o.get('stage',0))
            if context not in context_ids:context_ids[context]=len(contexts);contexts.append(context)
            ident=context_ids[context]
            if ident not in ids:ids.append(ident)
        description=(r['status'],r['classification'],r['duplicate_of'],r['note'])
        if description not in description_ids:description_ids[description]=len(descriptions);descriptions.append(description)
        rows.append([r['index'],r['resource_index'],*r['source_rect'],r['attributes'],ids,
                     len(evidence),evidence[0]['frame'],int(evidence[0]['command_address'],16),description_ids[description]])
    data={k:v for k,v in manifest.items() if k!='observed'}
    script='window.MUSHI_CATALOG='+json.dumps(data,separators=(',',':'))+';\n'
    script+='(()=>{const contexts='+json.dumps(contexts,separators=(',',':'))+';\n'
    script+='const descriptions='+json.dumps(descriptions,separators=(',',':'))+';\n'
    script+='window.MUSHI_CATALOG.observed='+json.dumps(rows,separators=(',',':'))+'''.map(r=>{
const [index,resource_index,x,y,width,height,attributes,ids,observation_count,frame,address,description]=r;
const id='draw-'+String(index).padStart(5,'0'),resource_id='u2-'+String(resource_index).padStart(4,'0');
const [capture,mode,character,shot,runtime,stage]=contexts[ids[0]];
const [status,classification,duplicate_of,note]=descriptions[description];
return {id,index,resource_index,resource_id,width,height,source_rect:[x,y,width,height],attributes,
source:'observed/'+id+'.png',thumbnail:'observed/thumbs/'+id+'.png',metadata:'observed/metadata/'+id+'.json',
status,classification,duplicate_of,note,
compression:window.MUSHI_CATALOG.resources[resource_index].compression,
native_stages:[...new Set(ids.filter(i=>contexts[i][4]==='native-aot').map(i=>contexts[i][5]).filter(s=>s>0))].sort((a,b)=>a-b),
runtime_kinds:[...new Set(ids.map(i=>contexts[i][4]))],
search_context:ids.map(i=>contexts[i].join(' ')+' '+(contexts[i][5]>0?'stage '+contexts[i][5]:'menus ending')).join(' '),
observation_count,observations:[{capture,mode,character,shot,runtime,stage,frame,command_address:'0x'+address.toString(16).padStart(8,'0')}]};
});})();\n'''
    (output/'catalog-data.js').write_text(script)


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
    write_manifest(output,manifest)
    write_json(output / "coverage.json", coverage)
    write_json(program_dir / "program.json", program_info)
    # Static data script allows offline browsing from file:// as well as HTTP.
    write_browser_data(output,manifest)
    web = Path(__file__).parent / "web"
    for name in ("index.html", "catalog.css", "catalog.js"):
        shutil.copyfile(web / name, output / name)
    print(json.dumps(coverage, indent=2))
    print(output / "index.html")
    return manifest
