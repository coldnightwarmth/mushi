"""Publish only sequences whose order/lifetime were verified in original code."""
import csv
import gzip
import hashlib
import json
from pathlib import Path
import shutil
from .catalog import read_manifest, write_manifest, write_browser_data, write_json


def export(trace: Path, catalog: Path):
    rows=list(csv.DictReader(trace.open(),delimiter='\t'))
    frames=json.loads(gzip.decompress((catalog/'frames/frames-full.json.gz').read_bytes()))
    variants=[]
    for variant in range(4):
        ticks=[{k:int(v) for k,v in r.items()} for r in rows if int(r['variant'])==variant]
        assert len(ticks)==8 and [r['tick'] for r in ticks]==list(range(8))
        assert [r['continue'] for r in ticks]==[1]*7+[0]
        assert len({r['glow'] for r in ticks})==1
        variants.append(dict(index=variant,primary_frames=[r['primary'] for r in ticks],
                             glow_frame=ticks[0]['glow'],source_table_address=f'0x{0xc285e90+variant*2:08x}',
                             primary_blend_arguments=[1,3,96,0],primary_tint='0x808080',
                             glow_blend_arguments=[2,1,48,0],glow_tint='0x807020',
                             glow_position='Previous tick position; primary is at the updated position'))
    sequences=[];seen={}
    for variant in variants:
        key=tuple(variant['primary_frames'])
        if key in seen:
            sequences[seen[key]]['variants'].append(variant['index']);continue
        index=len(sequences);seen[key]=index;ident=f'burst-{index:02d}'
        sequence=dict(id=ident,label=f'Green burst {index+1}',variants=[variant['index']],
                      frame_ids=[frames[i]['id'] for i in key],frames=[dict(id=frames[i]['id'],
                      source='../frames/'+frames[i]['source'],width=frames[i]['width'],height=frames[i]['height'],
                      metadata='../frames/'+frames[i]['metadata'],ticks=1) for i in key],
                      source_callback='0x0c07bf60',source_scheduler='0x0c07b8c0',loop=False,
                      ticks=8,frame_counter_offset='0x6e',countdown_offset='0x70',delay_offset='0x71',
                      initial_delay=0,status='verified-primary-layer-sequence',
                      metadata=f'{ident}.json',
                      note='Frame order and one active callback tick per frame are verified in original code. This preview shows the primary layer only. The original effect also draws a tinted glow at its previous position. Preview speed is adjustable and does not establish hardware timing.')
        sequences.append(sequence)
    coverage=dict(verified_primary_sequences=len(sequences),verified_effect_variants=4,
                  frame_references=sum(len(s['frames']) for s in sequences),
                  original_callback_fixtures=1024,original_callback_ticks=239360,
                  tested_delay_bytes=256,trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(),
                  rendering_comparison=False,
                  verification_scope='Original callback frame IDs, glow IDs, motion offsets, signed countdown and termination. Renderer is stubbed; preview is not a complete blended effect.')
    output=catalog/'animations';output.mkdir(parents=True,exist_ok=True)
    for s in sequences:write_json(output/s['metadata'],s)
    manifest=dict(schema=1,game='Mushihimesama Futari 1.5',coverage=coverage,sequences=sequences,variants=variants)
    write_json(output/'catalog.json',manifest)
    (output/'animations-data.js').write_text('window.MUSHI_ANIMATIONS='+json.dumps(manifest,separators=(',',':'))+';\n')
    web=Path(__file__).parent/'web'
    for name in ('animations.html','animations.js','animations.css'):
        shutil.copyfile(web/name,output/('index.html' if name=='animations.html' else name))
    for name in ('index.html','catalog.css','catalog.js'):
        shutil.copyfile(web/name,catalog/name)
    shutil.copyfile(web/'frames.html',catalog/'frames/index.html')
    main=read_manifest(catalog);main['animation_catalog']='animations/catalog.json'
    main['coverage']['verified_animation_sequences']=len(sequences)
    main['coverage']['verified_effect_variants']=4
    write_manifest(catalog,main);write_browser_data(catalog,main);write_json(catalog/'coverage.json',main['coverage'])
    validate_animations(output)
    return coverage


def validate_animations(output: Path):
    data=json.loads((output/'catalog.json').read_text())
    for sequence in data['sequences']:
        assert json.loads((output/sequence['metadata']).read_text())==sequence
        assert len(sequence['frames'])==sequence['ticks']==8 and not sequence['loop']
        for frame in sequence['frames']:
            assert (output/frame['source']).is_file()
            metadata=json.loads((output/frame['metadata']).read_text())
            assert metadata['id']==frame['id'] and metadata['width']==frame['width'] and metadata['height']==frame['height']
        for variant in sequence['variants']:
            assert [f'frame-{i:05d}' for i in data['variants'][variant]['primary_frames']]==sequence['frame_ids']
    for variant in data['variants']:
        assert (output/f"../frames/images/frame-{variant['glow_frame']:05d}.png").is_file()
    return dict(primary_sequences=len(data['sequences']),variants=len(data['variants']),frame_links_exact=True)
