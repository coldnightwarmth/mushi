"""Merge byte-exact native campaign source rectangles into the asset catalog."""
import csv
import json
from pathlib import Path
from PIL import Image
from .catalog import write_json,write_browser_data,read_manifest,write_manifest

def export(catalog: Path, prefixes: list[Path]):
    manifest=read_manifest(catalog)
    for directory in ('observed','observed/thumbs','observed/metadata'):
        (catalog/directory).mkdir(parents=True,exist_ok=True)
    records=manifest.get('observed',[])
    by_key={(r['resource_index'],*r['source_rect']):r for r in records}
    native_matches=set(manifest['coverage'].get('native_validated_resource_indices',[]))
    runs={r['capture']:r for r in manifest.get('observations',{}).get('native_runs',[])}
    images={};blank=0
    for prefix in prefixes:
        run=json.loads(prefix.with_suffix('.run.json').read_text())
        verification=json.loads(prefix.with_suffix('.verification.json').read_text())
        if not verification['all_clear'] or not verification['returned_to_attract']:
            raise ValueError(f'{prefix}: incomplete campaign')
        capture='native-'+run['route']+'-all-stages'
        stats=json.loads(prefix.with_suffix('.assets.json').read_text())
        native_matches.update(stats['matched_resources'])
        entries={}
        for row in csv.DictReader(prefix.with_suffix('.regions.tsv').open(),delimiter='\t'):
            key=tuple(int(row[k]) for k in ('resource','x','y','width','height'))
            resource,x,y,w,h=key
            if resource not in images:
                with Image.open(catalog/manifest['resources'][resource]['source']) as im:images[resource]=im.copy()
            if key not in by_key:
                crop=images[resource].crop((x,y,x+w,y+h))
                if crop.getbbox() is None:blank+=1;continue
                index=len(records);ident=f'draw-{index:05d}'
                crop.save(catalog/'observed'/f'{ident}.png')
                preview=crop.transpose(Image.Transpose.ROTATE_90);preview.thumbnail((160,160),Image.Resampling.NEAREST)
                preview.save(catalog/'observed/thumbs'/f'{ident}.png')
                r=dict(id=ident,index=index,resource_index=resource,resource_id=f'u2-{resource:04d}',width=w,height=h,
                       source_rect=[x,y,w,h],attributes=[],observations=[],source=f'observed/{ident}.png',
                       thumbnail=f'observed/thumbs/{ident}.png',metadata=f'observed/metadata/{ident}.json',
                       status='observed-draw-region',classification='unclassified',duplicate_of=None,
                       compression=manifest['resources'][resource]['compression'],
                       note='Native game draw source matched byte-for-byte to the complete ROM sheet. A draw region may be a clipped tile, text, effect or partial sprite; animation assembly is unverified.')
                records.append(r);by_key[key]=r
            r=by_key[key];attribute=int(row['attributes'])
            if attribute not in r['attributes']:r['attributes'].append(attribute);r['attributes'].sort()
            stage=int(row['stage'])+1
            context=(r['id'],stage)
            first,last,count=int(row['first_frame']),int(row['last_frame']),int(row['draws'])
            if context not in entries:
                entries[context]=dict(capture=capture,frame=first,last_frame=last,draw_count=count,
                    mode=run['mode'],character=run['character'],shot=run['shot'],runtime='native-aot',stage=stage,
                    command_address=f"0x{int(row['command_address']):08x}")
            else:
                e=entries[context];e['draw_count']+=count;e['last_frame']=max(e['last_frame'],last)
                if first<e['frame']:e['frame']=first;e['command_address']=f"0x{int(row['command_address']):08x}"
        for r in records:
            r['observations']=[o for o in r['observations'] if o['capture']!=capture]
        record_ids={r['id']:r for r in records}
        for (ident,_),entry in entries.items():record_ids[ident]['observations'].append(entry)
        runs[capture]=dict(capture=capture,**run,**{k:verification[k] for k in ('all_clear','ending_frame','attract_frame','stages','input_sha256')},
                           matched_resources=len(stats['matched_resources']),contexts=stats['contexts'])
        print(f'{capture}: {len(records)} distinct rectangles; {len(native_matches)} matched sheets',flush=True)
    for r in records:
        r['native_stages']=sorted({o['stage'] for o in r['observations'] if o.get('runtime')=='native-aot' and o.get('stage',0)>0})
        write_json(catalog/r['metadata'],r)
    resource_stages={}
    for r in records:resource_stages.setdefault(r['resource_index'],set()).update(r['native_stages'])
    for r in manifest['resources']:
        r['native_validated']=r['index'] in native_matches;r['native_stages']=sorted(resource_stages.get(r['index'],set()))
        write_json(catalog/'metadata'/f"{r['id']}.json",r)
    manifest['observed']=records
    manifest.setdefault('observations',{})['native_runs']=list(runs.values())
    manifest['observations']['native_scope']='Every draw in four native Original-mode campaigns, including all five stages and epilogues. Source pages match ROM pixels exactly. Dynamic/cross-page sources remain unmapped; no inferred multipart assembly or animation timing.'
    manifest['coverage'].update(observed_draw_regions=len(records),native_validated_resources=len(native_matches),
        native_validated_resource_indices=sorted(native_matches),native_campaigns=len(runs),native_verified_stages=[1,2,3,4,5],
        native_gameplay_complete=True,native_gameplay_scope='Original mode, Reco/Palm, Normal/Abnormal; native AOT. Hardware slowdown and other modes unverified.')
    write_manifest(catalog,manifest);write_json(catalog/'coverage.json',manifest['coverage'])
    write_json(catalog/'observations.json',manifest['observations']);write_browser_data(catalog,manifest)
    return manifest
