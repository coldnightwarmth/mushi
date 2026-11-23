"""Sound phrase extraction with directory aliases and exact ROM provenance."""
import csv
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import wave

from .catalog import read_manifest, write_manifest, write_browser_data, write_json


def export(sound: bytes, decoded: Path, catalog: Path):
    output = catalog / 'audio'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'metadata').mkdir(exist_ok=True)
    records = []
    for row in csv.DictReader((decoded / 'phrases.tsv').open(), delimiter='\t'):
        index, alias, offset = (int(row[k]) for k in ('index', 'alias', 'offset'))
        ident = f'phrase-{index:03d}'
        if alias >= 0:
            original = records[alias]
            record = dict(original, id=ident, index=index, duplicate_of=original['id'],
                          directory_offset=index*4, metadata=f'metadata/{ident}.json')
        else:
            samples, channels, end = (int(row[k]) for k in ('samples', 'channels', 'end_bit'))
            source = f'{ident}.wav' if samples else None
            if source:
                shutil.copyfile(decoded / f'phrase-{index}.wav', output / source)
            record = dict(id=ident, index=index, duplicate_of=None, source=source,
                          metadata=f'metadata/{ident}.json', directory_offset=index*4,
                          directory_word=int(row['entry']), source_offset=offset, end_bit=end,
                          compressed_sha256=hashlib.sha256(sound[offset:(end+7)//8]).hexdigest(),
                          sample_rate=16000, channels=channels, samples=samples,
                          duration_seconds=samples / max(1, channels) / 16000,
                          decoded_frames=int(row['frames']),
                          header_rates=[int(v) for v in row['header_rates'].split(',') if v],
                          terminated=row['terminated'],
                          wav_sha256=hashlib.sha256((output/source).read_bytes()).hexdigest() if source else None,
                          status='decoded-sound-phrase' if source else 'empty-phrase',
                          note='Native AMM decode from the original sound directory. Phrase IDs are verified; names and musical roles are not assigned. Sequences can combine multiple phrases.')
        records.append(record)
        write_json(output / record['metadata'], record)

    # Preserve all sequencer commands, including delays and end markers. Their
    # order is explicit in the ROM; assigning song names is a separate task.
    sequences, seen = [], {}
    for index in range(256):
        table = 0x400 + index*4
        offset = int.from_bytes(sound[table+1:table+4], 'big')
        if offset in seen:
            sequences.append(dict(index=index, source_offset=offset, duplicate_of=seen[offset]))
            continue
        seen[offset] = index
        commands = []
        for address in range(offset, len(sound)-1, 2):
            register, value = sound[address:address+2]
            commands.append([register, value])
            if register == 15:
                break
        else:
            raise ValueError(f'Unterminated sound sequence {index}')
        sequences.append(dict(index=index, directory_offset=table, source_offset=offset,
                              end_offset=address+2, duplicate_of=None, commands=commands,
                              sha256=hashlib.sha256(sound[offset:address+2]).hexdigest()))
    (output/'sequences.json.gz').write_bytes(gzip.compress(json.dumps(sequences,separators=(',',':')).encode(),mtime=0))
    unique = [r for r in records if r['duplicate_of'] is None]
    coverage = dict(directory_entries=256, unique_entries=len(unique),
                    decoded_phrases=sum(bool(r['source']) for r in unique),
                    empty_entries=sum(not r['source'] for r in unique),
                    decoded_samples=sum(r['samples'] for r in unique),
                    sequence_directory_entries=256, unique_sequences=len(seen),
                    named_sounds=0, assembled_soundtracks=0,
                    native_unity_gain_samples_exact=True,
                    sample_rate=16000, channels=1,
                    decoder='The native build’s BSD-licensed AMM decoder; no runtime emulator',
                    sound_bank_sha256=hashlib.sha256(sound).hexdigest())
    manifest = dict(game='Mushihimesama Futari 1.5', coverage=coverage,
                    phrases=records, sequences='sequences.json.gz')
    write_json(output/'catalog.json',manifest)
    (output/'audio-data.js').write_text('window.MUSHI_AUDIO='+json.dumps(manifest,separators=(',',':'))+';\n')
    web = Path(__file__).parent/'web'
    for name in ('audio.html','audio.js','audio.css'):
        shutil.copyfile(web/name, output/('index.html' if name=='audio.html' else name))
    for name in ('index.html','catalog.css','catalog.js'):
        shutil.copyfile(web/name, catalog/name)
    main = read_manifest(catalog)
    main['audio_catalog']='audio/catalog.json'
    main['coverage']['decoded_sound_phrases']=coverage['decoded_phrases']
    write_manifest(catalog,main);write_browser_data(catalog,main)
    write_json(catalog/'coverage.json',main['coverage'])
    validate_audio(output)
    return coverage


def validate_audio(output: Path):
    manifest = json.loads((output/'catalog.json').read_text())
    records = manifest['phrases']; assert len(records)==256
    for record in records:
        assert json.loads((output/record['metadata']).read_text())==record
        if record['duplicate_of'] is not None:
            original=next(r for r in records if r['id']==record['duplicate_of'])
            assert original['source']==record['source']
            continue
        if not record['source']:
            assert record['samples']==0
            continue
        file=output/record['source']
        assert hashlib.sha256(file.read_bytes()).hexdigest()==record['wav_sha256']
        with wave.open(str(file),'rb') as stream:
            assert stream.getframerate()==16000 and stream.getnchannels()==record['channels']
            assert stream.getsampwidth()==2 and stream.getnframes()*stream.getnchannels()==record['samples']
        assert record['terminated']=='end-marker'
    sequences=json.loads(gzip.decompress((output/manifest['sequences']).read_bytes()))
    assert len(sequences)==256
    assert all(s.get('duplicate_of') is not None or s['commands'][-1][0]==15 for s in sequences)
    return dict(phrases=manifest['coverage']['decoded_phrases'], directory_entries=256,
                wav_hashes_exact=True, wav_headers_verified=True, sequences_terminated=True)
