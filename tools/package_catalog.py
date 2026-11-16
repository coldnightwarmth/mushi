#!/usr/bin/env python3
"""Package a validated offline catalog, excluding ROMs and executable code dumps."""
import argparse
from pathlib import Path
import sys
from zipfile import ZipFile,ZIP_DEFLATED

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from mushi.validation import validate


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--catalog',type=Path,default=ROOT/'build/catalog')
    p.add_argument('--output',type=Path,default=ROOT/'build/releases/futari15-asset-catalog.zip')
    args=p.parse_args();validate(args.catalog);args.output.parent.mkdir(parents=True,exist_ok=True)
    with ZipFile(args.output,'w',compression=ZIP_DEFLATED,compresslevel=6) as archive:
        for file in sorted(args.catalog.rglob('*')):
            if file.is_file():archive.write(file,Path('futari15-asset-catalog')/file.relative_to(args.catalog))
    print(f'{args.output} ({args.output.stat().st_size:,} bytes)')


if __name__=='__main__':main()
