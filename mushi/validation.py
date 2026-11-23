"""Validate the exported catalog against its pixel and provenance contracts."""
from pathlib import Path
from collections import OrderedDict
import gzip
import json
from PIL import Image
from .json_stream import manifest_records


def validate(path: Path):
    manifest={};sources=OrderedDict();ids=set();observed=0
    def check(record,resources):
        assert record['id'] not in ids;ids.add(record['id'])
        with Image.open(path/record['source']) as im:
            assert im.mode=='RGBA' and im.size==(record['width'],record['height']),record['id']
            pixels=im.copy()
        with Image.open(path/record['thumbnail']) as thumb:
            assert thumb.mode=='RGBA' and max(thumb.size)<=160,record['id']
        meta=record.get('metadata',f"metadata/{record['id']}.json")
        assert json.loads((path/meta).read_text())==record,record['id']
        if 'source_rect' in record:
            index=record['resource_index']
            if index not in sources:
                with Image.open(path/resources[index]['source']) as source:sources[index]=source.copy()
                if len(sources)>32:sources.popitem(last=False)
            else:sources.move_to_end(index)
            x,y,w,h=record['source_rect']
            assert 0<=x and 0<=y and x+w<=sources[index].width and y+h<=sources[index].height
            assert sources[index].crop((x,y,x+w,y+h)).tobytes()==pixels.tobytes(),record['id']
            assert record['observations'],record['id']
    full=path/'catalog-full.json.gz'
    opener=gzip.open if full.exists() else open
    with opener(full if full.exists() else path/'catalog.json','rt',encoding='utf-8') as stream:
        for key,value in manifest_records(stream):
            if key=='observed_record':
                check(value,manifest['resources']);observed+=1
            else:
                manifest[key]=value
                if key=='resources':
                    assert [r['index'] for r in value]==list(range(len(value)))
                    for record in value:check(record,value)
    resources=manifest['resources']
    assert len(resources)==manifest['coverage']['decoded_resources']==manifest['coverage']['resource_entries']
    assert observed==manifest['coverage'].get('observed_draw_regions',0)
    for file in ('index.html','catalog.css','catalog.js','catalog-data.js','coverage.json'):
        assert (path/file).is_file(),file
    result=dict(resource_images=len(resources),observed_images=observed,exact_source_crops=True,all_links_present=True)
    if manifest.get('audio_catalog'):
        from .audio_catalog import validate_audio
        result['audio']=validate_audio(path/Path(manifest['audio_catalog']).parent)
    if manifest.get('frame_catalog'):
        from .frame_catalog import validate_frames
        result['frames']=validate_frames(path/Path(manifest['frame_catalog']).parent)
    if manifest.get('animation_catalog'):
        from .animation_catalog import validate_animations
        result['animations']=validate_animations(path/Path(manifest['animation_catalog']).parent)
    print(json.dumps(result,indent=2))
    return result
