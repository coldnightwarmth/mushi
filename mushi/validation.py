"""Validate the exported catalog against its pixel and provenance contracts."""
from pathlib import Path
import json
from PIL import Image
from .catalog import read_manifest


def validate(path: Path):
    manifest=read_manifest(path)
    resources=manifest['resources'];observed=manifest.get('observed',[])
    assert len(resources)==manifest['coverage']['decoded_resources']==manifest['coverage']['resource_entries']
    assert [r['index'] for r in resources]==list(range(len(resources)))
    sources={};ids=set()
    for record in resources+observed:
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
            x,y,w,h=record['source_rect']
            assert 0<=x and 0<=y and x+w<=sources[index].width and y+h<=sources[index].height
            assert sources[index].crop((x,y,x+w,y+h)).tobytes()==pixels.tobytes(),record['id']
            assert record['observations'],record['id']
    assert len(observed)==manifest['coverage'].get('observed_draw_regions',0)
    for file in ('index.html','catalog.css','catalog.js','catalog-data.js','coverage.json'):
        assert (path/file).is_file(),file
    result=dict(resource_images=len(resources),observed_images=len(observed),exact_source_crops=True,all_links_present=True)
    print(json.dumps(result,indent=2))
    return result
