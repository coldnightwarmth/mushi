"""Recover exact draw rectangles by matching original VRAM pages to ROM sheets.

No connected-component segmentation, guessed grids or guessed animation timing.
Observed draws are evidence of usage at those frames, not exhaustive families.
"""
from hashlib import sha256
from pathlib import Path
import csv
import json
import numpy as np
from PIL import Image
from .blitter import commands
from .catalog import write_json


def argb_to_vram(rgba):
    a=rgba.astype(np.uint32)
    return ((a[:,:,3]>0).astype(np.uint32)*(1<<29) | (a[:,:,0]<<16) | (a[:,:,1]<<8) | a[:,:,2]).astype('<u4')


def export(catalog: Path, captures: list[Path]):
    manifest=json.loads((catalog/'catalog.json').read_text())
    hashes={}
    for record in manifest['resources']:
        with Image.open(catalog/record['source']) as im:
            raw=argb_to_vram(np.asarray(im))
        hashes[sha256(raw.tobytes()).digest()]=record['index']
    regions={};validated=set();reports=[]
    for capture in captures:
        run=json.loads((capture/'run.json').read_text())
        for row in csv.DictReader((capture/'graphics.tsv').open(),delimiter='\t'):
            frame=int(row['frame']);vram_path=capture/f'vram-{frame:05d}.bin'
            if not vram_path.exists():continue
            if int(row['vram_element_size'])!=4 or int(row['vram_count'])!=8192*4096:
                raise ValueError("Unsupported reference VRAM layout")
            vram=np.memmap(vram_path,dtype='<u4',mode='r',shape=(4096,8192))
            pages={}
            for y in range(0,4096,256):
                for x in range(0,8192,256):
                    resource=hashes.get(sha256(vram[y:y+256,x:x+256].tobytes()).digest())
                    if resource is not None:
                        pages[x,y]=resource;validated.add(resource)
            sx,sy=int(row['scroll_x']),int(row['scroll_y'])
            pixels=vram[sy:sy+240,sx:sx+320]
            rgb=np.stack([(pixels>>16)&255,(pixels>>8)&255,pixels&255],axis=-1).astype(np.uint8)
            upright=np.rot90(rgb)
            with Image.open(capture/f'frame-{frame:05d}.png') as screenshot:
                exact=np.array_equal(upright,np.asarray(screenshot.convert('RGB')))
            if not exact:raise AssertionError(f"Framebuffer mismatch: {capture.name}/{frame}")
            mapped,unmapped=0,0
            ram=(capture/f'ram-{frame:05d}.bin').read_bytes()
            for command in commands(ram,int(row['list_address'],16)):
                if command['kind']!='draw':continue
                x,y,w,h=command['src_x'],command['src_y'],command['width'],command['height']
                px,py=x//256*256,y//256*256
                resource=pages.get((px,py))
                if resource is None or x+w>px+256 or y+h>py+256:
                    unmapped+=1;continue
                mapped+=1
                key=resource,x-px,y-py,w,h
                entry=regions.setdefault(key,dict(observations=[],attributes=set()))
                evidence=dict(capture=capture.name,frame=frame,mode=run['mode'],character=run['character'],shot=run['shot'],
                              command_address=f"0x{command['address']:08x}")
                if evidence not in entry['observations']:entry['observations'].append(evidence)
                entry['attributes'].add(command['attributes'])
            reports.append(dict(capture=capture.name,frame=frame,matched_pages=len(pages),mapped_draws=mapped,
                                unmapped_draws=unmapped,framebuffer_exact=exact))
    for folder in ('observed','observed/thumbs','observed/metadata'):(catalog/folder).mkdir(exist_ok=True)
    records=[];blank=0
    for (resource,x,y,w,h),entry in sorted(regions.items()):
        with Image.open(catalog/manifest['resources'][resource]['source']) as source:
            im=source.crop((x,y,x+w,y+h))
        if im.getbbox() is None:
            blank+=1;continue
        ident=f'draw-{len(records):05d}'
        im.save(catalog/'observed'/f'{ident}.png')
        preview=im.transpose(Image.Transpose.ROTATE_90);preview.thumbnail((160,160),Image.Resampling.NEAREST)
        preview.save(catalog/'observed/thumbs'/f'{ident}.png')
        record=dict(id=ident,index=len(records),resource_index=resource,resource_id=f'u2-{resource:04d}',
                    width=w,height=h,source_rect=[x,y,w,h],attributes=sorted(entry['attributes']),observations=entry['observations'],
                    source=f'observed/{ident}.png',thumbnail=f'observed/thumbs/{ident}.png',metadata=f'observed/metadata/{ident}.json',
                    status='observed-draw-region',classification='unclassified',duplicate_of=None,
                    compression=manifest['resources'][resource]['compression'],
                    note=f'Original blitter source rectangle matched byte-for-byte to u2-{resource:04d}. This is a draw region, not a verified animation sequence.')
        write_json(catalog/record['metadata'],record);records.append(record)
    manifest['observed']=records
    manifest['observations']=dict(captures=reports,validated_resource_indices=sorted(validated),blank_regions=blank,
        scope='Finite reference captures only. Draws crossing resource pages and draws from dynamic VRAM are counted as unmapped. No inferred frame timing or multipart assembly.')
    manifest['coverage'].update(runtime_validated_resources=len(validated),observed_draw_regions=len(records),verified_framebuffers=len(reports))
    for resource in manifest['resources']:
        resource['runtime_validated']=resource['index'] in validated
        write_json(catalog/'metadata'/f"{resource['id']}.json",resource)
    write_json(catalog/'catalog.json',manifest);write_json(catalog/'coverage.json',manifest['coverage'])
    write_json(catalog/'observations.json',manifest['observations'])
    (catalog/'catalog-data.js').write_text('window.MUSHI_CATALOG='+json.dumps(manifest,separators=(',',':'))+';\n')
    print(json.dumps(manifest['coverage'],indent=2))
    return manifest
