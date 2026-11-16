#!/usr/bin/env python3
"""Compile and compare the native decoder on every compressed ROM resource."""
import argparse
import ctypes
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from mushi.compression import decompress
from mushi.nand import Nand
from mushi.rom import load_roms, swap_words


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("rom",type=Path);args=p.parse_args()
    out=ROOT/"build/native";out.mkdir(parents=True,exist_ok=True)
    library=out/"libmushi.dylib"
    subprocess.run(["clang","-std=c11","-O2","-Wall","-Wextra","-Werror","-dynamiclib",str(ROOT/"native/lz.c"),"-o",str(library)],check=True)
    lib=ctypes.CDLL(str(library));decode=lib.mushi_lz_decode
    decode.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_size_t),ctypes.POINTER(ctypes.c_size_t)]
    decode.restype=ctypes.c_int
    roms,_=load_roms(args.rom);nand=Nand(roms["futari15_u2"])
    inputs=[("program",swap_words(roms["futari15_u4"])[0x51000:])]
    inputs += [(f"u2-{r.index:04d}",nand.read(r)[0]) for r in nand.resources if r.compression]
    total=0
    for name,data in inputs:
        expected=decompress(data);dst=ctypes.create_string_buffer(len(expected.data));written=ctypes.c_size_t();consumed=ctypes.c_size_t()
        if decode(data,len(data),dst,len(dst),ctypes.byref(written),ctypes.byref(consumed)) != 0:
            raise AssertionError(f"Native decoder rejected {name}")
        assert dst.raw==expected.data and written.value==len(expected.data) and consumed.value==expected.consumed,name
        total+=written.value
    # Native failure paths, including capacity and corrupt reference bounds.
    bad=[b"",struct.pack(">III",4,1,13)+b"\x80\0\0",struct.pack(">III",4,1,13)+b"\x80\0\x20",
         struct.pack(">III",2,2,13)+b"\x40A\0\x20",struct.pack(">III",2,2,13)+b"\0A"]
    for data in bad:
        dst=ctypes.create_string_buffer(10);written=ctypes.c_size_t();consumed=ctypes.c_size_t()
        assert decode(data,len(data),dst,len(dst),ctypes.byref(written),ctypes.byref(consumed))==-1
    data=struct.pack(">III",1,1,13)+b"\0A"
    assert decode(data,len(data),dst,0,ctypes.byref(written),ctypes.byref(consumed))==-1
    result=dict(streams=len(inputs),decoded_bytes=total,byte_exact=True,malformed_cases=len(bad)+1,
                oracle="independent Python implementation; live original-program validation recorded separately")
    (out/"verification.json").write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps(result,indent=2))


if __name__ == "__main__":main()
