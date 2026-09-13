#!/usr/bin/env python3
"""Explicit source generation, separate from the checked native build.

--apply reproduces reviewed generated bodies. --check is read-only. Neither mode
compiles, processes artifacts, generates keys/proofs, or contacts a chain.
"""
from pathlib import Path
import argparse,json,subprocess,sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
def run(name,*args):
 subprocess.run([sys.executable,str(HERE/name),*map(str,args)],cwd=ROOT,check=True)
def main():
 parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
 mode.add_argument('--apply',action='store_true');mode.add_argument('--check',action='store_true');args=parser.parse_args()
 if args.apply:
  run('generate_facades.py')
  run('generate-backend-move.py','--apply')
  run('generate-backend-plans.py','--apply')
  run('build-backend.py')
 for package in ['libs','prospect_original_libs']:
  manifest=HERE/f'generated/field-buffer-{package}.json';row=json.loads(manifest.read_text())
  call=['--output',ROOT/f'contracts/{package}/src/field_buffer.nr','--widths',','.join(map(str,row['widths'])),'--unroll',','.join(map(str,row['unrolled'])),'--manifest',manifest]
  if not args.apply:call.append('--check')
  run('generate-field-buffer.py',*call)
 run('generate-backend-move.py','--check');run('generate-backend-plans.py','--check')
 run('validate-selected-source.py','--root',ROOT)
if __name__=='__main__':main()
