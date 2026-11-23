"""Export the original frame directory, distinct from observed draw fragments."""
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import struct
from collections import OrderedDict
from PIL import Image
from .json_stream import array_records

from .catalog import read_manifest, write_manifest, write_browser_data, write_json

TABLE = 0x20bf14
COUNT = 0x285028
PROGRAM_SHA256 = '2d21872e06fd4d1a1e1505ae0dc0e1bfeff78f0730eb9730e5787347f97c6f35'


def export(program: bytes, catalog: Path):
    if hashlib.sha256(program).hexdigest() != PROGRAM_SHA256:
        raise ValueError('Frame layout is verified only for the supplied Futari 1.5 program')
    main = read_manifest(catalog)
    output = catalog/'frames'
    for folder in (output, output/'images', output/'metadata'):
        folder.mkdir(parents=True, exist_ok=True)
    count = struct.unpack_from('>I', program, COUNT)[0]
    records, sheets, pixel_hashes, rectangles = [], {}, {}, set()
    for index in range(count):
        at = TABLE + index*10
        resource, x, y, width, height, ident = struct.unpack_from('>HBBHHH', program, at)
        assert ident == index and resource < len(main['resources'])
        assert width > 0 and height > 0 and x+width <= 256 and y+height <= 256
        if resource not in sheets:
            with Image.open(catalog/main['resources'][resource]['source']) as im:
                assert im.size == (256, 256) and im.mode == 'RGBA'
                sheets[resource] = im.copy()
        sx, sy, sw, sh = 256-y-height, x, height, width
        crop = sheets[resource].crop((sx, sy, sx+sw, sy+sh)).transpose(Image.Transpose.ROTATE_90)
        assert crop.size == (width, height)
        name = f'frame-{index:05d}'
        source, metadata = f'images/{name}.png', f'metadata/{name}.json'
        crop.save(output/source)
        digest = hashlib.sha256(struct.pack('>HH', width, height)+crop.tobytes()).hexdigest()
        duplicate = pixel_hashes.get(digest)
        pixel_hashes.setdefault(digest, name)
        rectangles.add((resource, sx, sy, sw, sh))
        record = dict(id=name, index=index, resource_index=resource, resource_id=f'u2-{resource:04d}',
                      width=width, height=height, upright_rect=[x, y, width, height],
                      source_rect=[sx, sy, sw, sh], source=source, metadata=metadata,
                      source_sheet='../'+main['resources'][resource]['source'],
                      resource_metadata='../metadata/'+f'u2-{resource:04d}.json',
                      descriptor_address=f'0x{0x0c000000+at:08x}', program_offset=at,
                      descriptor_hex=program[at:at+10].hex(), sha256=digest,
                      duplicate_of=duplicate, opaque_pixels=sum(a != 0 for a in crop.getchannel('A').getdata()),
                      status='original-frame-entry', classification='unclassified',
                      note='Original frame directory entry. PNG is upright; source_rect is in the unrotated sheet. Frame boundaries are verified against the compiled draw wrapper. IDs do not establish animation order, timing, or gameplay identity.')
        records.append(record)
        write_json(output/metadata, record)
        if (index+1) % 5000 == 0:
            print(f'Exported {index+1} / {count} original frame entries', flush=True)
    coverage = dict(frame_entries=count, distinct_source_rectangles=len(rectangles),
                    source_resources=len(sheets), unique_pixel_images=len(pixel_hashes),
                    duplicate_pixel_images=count-len(pixel_hashes),
                    empty_frames=sum(r['opaque_pixels'] == 0 for r in records),
                    pixels=sum(r['width']*r['height'] for r in records),
                    program_sha256=PROGRAM_SHA256, table_address=f'0x{0x0c000000+TABLE:08x}',
                    count_address=f'0x{0x0c000000+COUNT:08x}', record_bytes=10,
                    table_sha256=hashlib.sha256(program[TABLE:TABLE+count*10]).hexdigest(),
                    original_wrapper='0x0c063740', all_original_wrapper_arguments_exact=True,
                    native_directory_identity_entries=1201,
                    verified_animation_sequences=0)
    manifest = dict(schema=1, game='Mushihimesama Futari 1.5', coverage=coverage,
                    full_manifest='frames-full.json.gz')
    write_json(output/'catalog.json', manifest)
    (output/'frames-full.json.gz').write_bytes(gzip.compress(json.dumps(records, separators=(',', ':')).encode(), mtime=0))
    rows = [[r['resource_index'], *r['upright_rect'],
             int(r['duplicate_of'][6:]) if r['duplicate_of'] else None, r['opaque_pixels']] for r in records]
    (output/'frames-data.js').write_text('window.MUSHI_FRAMES='+json.dumps(dict(coverage=coverage, rows=rows), separators=(',', ':'))+';\n')
    web = Path(__file__).parent/'web'
    for name in ('frames.html', 'frames.js', 'frames.css'):
        shutil.copyfile(web/name, output/('index.html' if name == 'frames.html' else name))
    for name in ('index.html', 'catalog.css', 'catalog.js'):
        shutil.copyfile(web/name, catalog/name)
    main['frame_catalog'] = 'frames/catalog.json'
    main['coverage']['original_frame_entries'] = count
    main['coverage']['original_frame_resources'] = len(sheets)
    write_manifest(catalog, main); write_browser_data(catalog, main)
    write_json(catalog/'coverage.json', main['coverage'])
    coverage['validation'] = validate_frames(output)
    return coverage


def validate_frames(output: Path):
    manifest = json.loads((output/'catalog.json').read_text())
    sheets, directory, seen = OrderedDict(), bytearray(), {}
    count=0
    with gzip.open(output/manifest['full_manifest'],'rt',encoding='utf-8') as stream:
        for index, r in enumerate(array_records(stream)):
            count+=1
            assert r['index'] == index and r['id'] == f'frame-{index:05d}'
            assert json.loads((output/r['metadata']).read_text()) == r
            raw = bytes.fromhex(r['descriptor_hex']); directory.extend(raw)
            resource, x, y, w, h, ident = struct.unpack('>HBBHHH', raw)
            assert ident == index and resource == r['resource_index']
            assert r['upright_rect'] == [x, y, w, h]
            assert r['source_rect'] == [256-y-h, x, h, w]
            assert r['program_offset'] == TABLE+index*10
            assert r['descriptor_address'] == f'0x{0x0c000000+TABLE+index*10:08x}'
            if resource not in sheets:
                with Image.open(output/r['source_sheet']) as im: sheets[resource] = im.copy()
                if len(sheets)>32:sheets.popitem(last=False)
            else:sheets.move_to_end(resource)
            sx, sy, sw, sh = r['source_rect']
            assert 0 <= sx and 0 <= sy and sx+sw <= 256 and sy+sh <= 256
            expected = sheets[resource].crop((sx, sy, sx+sw, sy+sh)).transpose(Image.Transpose.ROTATE_90)
            with Image.open(output/r['source']) as actual:
                assert actual.mode == 'RGBA' and actual.size == (w, h)
                assert actual.tobytes() == expected.tobytes(), r['id']
                digest = hashlib.sha256(struct.pack('>HH', w, h)+actual.tobytes()).hexdigest()
                assert digest == r['sha256']
                assert sum(a != 0 for a in actual.getchannel('A').getdata()) == r['opaque_pixels']
            assert r['duplicate_of'] == seen.get(digest)
            seen.setdefault(digest, r['id'])
            assert (output/r['resource_metadata']).is_file()
    assert count==manifest['coverage']['frame_entries']
    assert hashlib.sha256(directory).hexdigest() == manifest['coverage']['table_sha256']
    for name in ('index.html', 'frames.js', 'frames.css', 'frames-data.js'):
        assert (output/name).is_file()
    return dict(frame_images=count, exact_upright_source_crops=True,
                original_descriptors_exact=True, pixel_hashes_exact=True, all_links_present=True)
