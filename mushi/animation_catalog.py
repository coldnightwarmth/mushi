"""Publish only sequences whose order/lifetime were verified in original code."""
import csv
import gzip
import hashlib
import json
from pathlib import Path
import shutil
from collections import defaultdict
from .catalog import read_manifest, write_manifest, write_browser_data, write_json


def particle_sequences(trace: Path, frames):
    """Collapse verified callback traces into six tracks with 17 fade profiles.

    Flips and fade choices are parameters, not additional animation families.
    Every exported tick comes from the original callback comparison trace.
    """
    histories = defaultdict(list)
    with trace.open() as stream:
        for row in csv.DictReader(stream, delimiter='\t'):
            row = {key: int(value) for key, value in row.items()}
            histories[row['type'], row['table'], row['initial_fade'], row['flip']].append(row)
    expected = {(kind, table, fade, flip) for kind in (0, 5) for table in range(3)
                for fade in range(239, 256) for flip in (0, 1)}
    assert set(histories) == expected
    sequences = []
    for kind in (0, 5):
        for table in range(3):
            profiles = []
            for fade in range(239, 256):
                ticks = histories[kind, table, fade, 0]
                flipped = histories[kind, table, fade, 1]
                assert [(r['frame'], r['fade'], r['continue']) for r in ticks] == [
                    (r['frame'], r['fade'], r['continue']) for r in flipped]
                assert [r['tick'] for r in ticks] == list(range(len(ticks)))
                assert [r['continue'] for r in ticks] == [1] * (len(ticks) - 1) + [0]
                timeline = []
                for tick in ticks[:-1]:
                    frame = frames[tick['frame']]
                    if timeline and timeline[-1]['id'] == frame['id']:
                        timeline[-1]['ticks'] += 1
                    else:
                        timeline.append(dict(id=frame['id'], source='../frames/'+frame['source'],
                                             width=frame['width'], height=frame['height'],
                                             metadata='../frames/'+frame['metadata'], ticks=1))
                profiles.append(dict(initial_fade=fade, ticks=len(ticks)-1, frames=timeline,
                                     updates=[dict(frame_id=frames[r['frame']]['id'], fade=r['fade'])
                                              for r in ticks[:-1]],
                                     rng_seeds_by_flip=[ticks[0]['seed'], flipped[0]['seed']],
                                     termination_tick=ticks[-1]['tick'],
                                     termination_fade=ticks[-1]['fade']))
            default = profiles[-1]
            ident = f'particle-{kind:02d}-{table:02d}'
            sequences.append(dict(
                id=ident, label=f'Particle {"slow" if kind == 5 else "fast"} · table {table+1}',
                particle_type=kind, table_index=table,
                source_table_address=f'0x{0xc28e2b0+table*24:08x}',
                source_initializer='0x0c099ef0' if kind == 5 else '0x0c099e00',
                source_callback='0x0c099fe0', source_scheduler='0x0c099ad0',
                frame_ids=[f['id'] for f in default['frames']], frames=default['frames'],
                ticks=default['ticks'], profiles=profiles, default_initial_fade=255,
                flip_choices=[0, 1], blend_arguments=[2, 1, 'current fade byte', 0],
                frame_counter_offset='0x03', countdown_offset='0x04', delay_offset='0x05',
                initial_delay=20 if kind == 5 else 3, loop=False,
                status='verified-primary-layer-sequence', metadata=f'{ident}.json',
                note='Original initializer and complete callback lifetimes verified for every fade/table/flip choice. '
                     'Frame advancement happens before drawing. Fade decreases by four each update and can end a slow track early. '
                     'Preview shows unflipped source frames and their verified durations; original blending, fade appearance, '
                     'movement and offscreen culling are not reproduced. Preview speed does not establish hardware timing.'))
    return sequences, dict(verified_particle_types=2, verified_particle_tracks=6,
                           verified_particle_timing_profiles=102,
                           particle_lifetime_fixtures=len(histories),
                           particle_callback_ticks=sum(map(len, histories.values())),
                           particle_draw_submissions=sum(len(t)-1 for t in histories.values()),
                           particle_trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest())


def export(trace: Path, catalog: Path, particle_trace: Path = None):
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
    particle_coverage = {}
    if particle_trace:
        particles, particle_coverage = particle_sequences(particle_trace, frames)
        sequences.extend(particles)
    coverage=dict(verified_primary_sequences=len(sequences),verified_effect_variants=4,
                  frame_references=sum(len(s['frames']) for s in sequences),
                  original_callback_fixtures=1024,original_callback_ticks=239360,
                  tested_delay_bytes=256,trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(),
                  rendering_comparison=False,
                  verification_scope='Original callback frame IDs, glow IDs, motion offsets, signed countdown and termination. '
                                     'Particle profiles also verify original RNG, initialization, fade, flip and blend arguments. '
                                     'Renderer is stubbed; previews are not complete blended effects.', **particle_coverage)
    output=catalog/'animations';output.mkdir(parents=True,exist_ok=True)
    for s in sequences:write_json(output/s['metadata'],s)
    if particle_trace:
        (output/'particle-callbacks.tsv.gz').write_bytes(gzip.compress(particle_trace.read_bytes(),mtime=0))
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
    for key in ('verified_particle_types', 'verified_particle_tracks', 'verified_particle_timing_profiles'):
        if key in coverage:main['coverage'][key]=coverage[key]
    write_manifest(catalog,main);write_browser_data(catalog,main);write_json(catalog/'coverage.json',main['coverage'])
    validate_animations(output)
    return coverage


def validate_animations(output: Path):
    data=json.loads((output/'catalog.json').read_text())
    if 'particle_trace_sha256' in data['coverage']:
        trace=gzip.decompress((output/'particle-callbacks.tsv.gz').read_bytes())
        assert hashlib.sha256(trace).hexdigest()==data['coverage']['particle_trace_sha256']
        assert len(trace.splitlines())-1==data['coverage']['particle_callback_ticks']
    for sequence in data['sequences']:
        assert json.loads((output/sequence['metadata']).read_text())==sequence
        assert not sequence['loop']
        assert sequence['frame_ids']==[f['id'] for f in sequence['frames']]
        profiles=sequence.get('profiles',[sequence])
        if 'profiles' in sequence:
            assert [p['initial_fade'] for p in profiles]==list(range(239,256))
            assert sequence['frames']==profiles[-1]['frames'] and sequence['ticks']==profiles[-1]['ticks']
        for profile in profiles:
            assert sum(f['ticks'] for f in profile['frames'])==profile['ticks']
            for frame in profile['frames']:
                assert frame['ticks']>0 and (output/frame['source']).is_file()
                metadata=json.loads((output/frame['metadata']).read_text())
                assert metadata['id']==frame['id'] and metadata['width']==frame['width'] and metadata['height']==frame['height']
            if 'updates' in profile:
                assert [f['id'] for f in profile['frames'] for _ in range(f['ticks'])]==[u['frame_id'] for u in profile['updates']]
                assert [u['fade'] for u in profile['updates']]==list(range(profile['initial_fade']-4,profile['initial_fade']-4*(profile['ticks']+1),-4))
                assert profile['termination_tick']==profile['ticks']
        for variant in sequence.get('variants',[]):
            assert [f'frame-{i:05d}' for i in data['variants'][variant]['primary_frames']]==sequence['frame_ids']
    for variant in data['variants']:
        assert (output/f"../frames/images/frame-{variant['glow_frame']:05d}.png").is_file()
    assert len(data['sequences'])==data['coverage']['verified_primary_sequences']
    return dict(primary_sequences=len(data['sequences']),variants=len(data['variants']),frame_links_exact=True,
                particle_timing_profiles=sum(len(s.get('profiles',[])) for s in data['sequences']))
