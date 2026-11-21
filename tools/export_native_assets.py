#!/usr/bin/env python3
"""Publishable sprite evidence from completed native campaign verification runs."""
import argparse
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from mushi.native_observations import export

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('campaigns',type=Path)
    p.add_argument('--catalog',type=Path,default=ROOT/'build/catalog')
    a=p.parse_args()
    prefixes=[a.campaigns/name for name in ('reco-normal','reco-abnormal','palm-normal','palm-abnormal')]
    export(a.catalog,prefixes)

if __name__=='__main__':main()
