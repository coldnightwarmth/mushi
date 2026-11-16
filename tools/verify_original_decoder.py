#!/usr/bin/env python3
"""Compare every compressed stream with the original SH3 decoder in isolation."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from mushi.rom import load_roms,swap_words
from mushi.nand import Nand
from mushi.compression import decompress


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--rom",type=Path,required=True);p.add_argument("--mame",type=Path,required=True)
    p.add_argument("--frameworks",type=Path)
    args=p.parse_args();out=ROOT/"build/decoder-original";out.mkdir(parents=True,exist_ok=True)
    roms,_=load_roms(args.rom);program=swap_words(roms["futari15_u4"]);nand=Nand(roms["futari15_u2"])
    cases=[("program",program[0x51000:])]+[(f"u2-{r.index:04d}",nand.read(r)[0]) for r in nand.resources if r.compression]
    records=[]
    with (out/"inputs.bin").open("wb") as inputs,(out/"expected.bin").open("wb") as expected:
        for name,data in cases:
            result=decompress(data)
            inputs.write(struct.pack(">II",len(data),len(result.data)));inputs.write(data);expected.write(result.data)
            records.append(dict(name=name,size=len(result.data),consumed=result.consumed,sha256=hashlib.sha256(result.data).hexdigest()))
    (out/"routine.bin").write_bytes(program[0x2ac4:0x2b56])
    env=os.environ.copy();env["MUSHI_DECODER_TEST"]=str(out)
    if args.frameworks:env["DYLD_FRAMEWORK_PATH"]=str(args.frameworks.resolve())
    command=[str(args.mame.resolve()),"futari15","-rompath",str(args.rom.resolve().parent),"-video","none","-sound","none",
             "-nothrottle","-nodrc","-skip_gameinfo","-autoboot_delay","0","-autoboot_script",str(ROOT/"tools/verify_decoder.lua"),
             "-cfg_directory",str(out/"cfg"),"-nvram_directory",str(out/"nvram"),"-seconds_to_run","300"]
    with (out/"run.log").open("w") as log:
        subprocess.run(command,env=env,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=600)
    with (out/"original-output.bin").open("rb") as actual:
        for record in records:
            data=actual.read(record["size"])
            if len(data)!=record["size"] or hashlib.sha256(data).hexdigest()!=record["sha256"]:
                raise AssertionError(f"Original SH3 output differs: {record['name']}")
        assert actual.read()==b""
    rows=list(csv.DictReader((out/"original.tsv").open(),delimiter="\t"))
    assert len(rows)==len(records)
    for row,record in zip(rows,records):
        assert int(row['return_size'])==record['size']
        assert int(row['destination_end'],16)==0x0c300000+record['size']
        assert int(row['source_end'],16)==0x0c600000+record['consumed']
    result=dict(entry="0x0c002ac4",oracle="Original SH3 instructions under MAME 0.286 interpreter; IRQs masked",streams=len(records),
                decoded_bytes=sum(r["size"] for r in records),byte_exact=True,return_register_and_end_pointers_exact=True,cases=records)
    (out/"verification.json").write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({k:v for k,v in result.items() if k!="cases"},indent=2))


if __name__ == "__main__":main()
