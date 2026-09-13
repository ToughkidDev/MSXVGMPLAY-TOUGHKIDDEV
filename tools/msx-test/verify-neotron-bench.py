#!/usr/bin/env python3
"""Verify compact streams, loop offsets and actual SIOS payloads from a run."""
import argparse
import array
import json
import re
import struct
import wave
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('label')
    parser.add_argument('--cases', nargs='+', help='Require exactly these completed cases')
    parser.add_argument('--require-pcm', action='store_true')
    parser.add_argument('--require-audio', action='store_true')
    args = parser.parse_args()
    root = args.directory
    cases = {r['name']: r for r in json.loads((root / 'manifest.json').read_text())}
    failures = []
    summaries = []
    for table in sorted(root.glob(f'{args.label}-*.segments')):
        case = table.name[len(args.label)+1:-len('.segments')]
        prefix = root / f'{args.label}-{case}'
        expected = cases[case.split('.')[0]]
        lines = table.read_text().splitlines()
        fields = dict(re.findall(r'(\w+)=(\d+)', lines[0]))
        size = int(fields['size'])
        actual = bytearray()
        slots = set()
        for line in lines[1:]:
            segment, slot = map(int, line.split())
            slots.add(slot)
            # The reference 1.5MB machine uses these two mapper slots.
            assert slot in (0x83, 0x8a), f'Unrecognised mapper slot {slot:02x}'
            name = 'Main_RAM' if slot == 0x83 else 'MegaFlashRom_SCC+_SD_memory_mapper'
            ram = Path(f'{prefix}.{name}.ram').read_bytes()
            actual.extend(ram[segment*16384:(segment+1)*16384])
        reference = (root / f"{expected['name']}.expected").read_bytes()
        equal = actual[:size] == reference
        loop_ok = 'loop' not in fields or int(fields['loop']) == (expected['loop']-0x1c if expected['loop'] is not None else 0)
        pcm_ok = None
        pcm_file = Path(f'{prefix}.pcm')
        if pcm_file.exists():
            data = (root / f"{expected['name']}.VGM").read_bytes()
            wanted = bytearray()
            for block in expected['blocks']:
                if block['type'] not in ('0x82', '0x83'): continue
                payload = data[block['dataOffset']:block['dataOffset']+block['size']-8]
                for p in range(0, len(payload), 256):
                    wanted += struct.pack('<BH', 1 if block['type']=='0x82' else 2, 256)
                    wanted += payload[p:p+256].ljust(256, b'\0')
            pcm_ok = pcm_file.read_bytes() == wanted
        audio = None
        wav = Path(f'{prefix}.wav')
        if wav.exists():
            with wave.open(str(wav)) as f:
                assert f.getsampwidth() == 2
                samples = array.array('h', f.readframes(f.getnframes()))
                audio = dict(seconds=round(f.getnframes()/f.getframerate(), 3),
                             peak=max(map(abs, samples), default=0),
                             rms=round((sum(s*s for s in samples)/max(1,len(samples)))**0.5, 2))
        passed = equal and loop_ok and pcm_ok is not False
        if args.require_pcm and pcm_ok is not True:
            passed = False
        if args.require_audio:
            synthetic = expected['source'].startswith('fixture:')
            passed = passed and audio is not None and audio['seconds'] >= 4.9
            if not synthetic:
                passed = passed and audio is not None and audio['rms'] > 0
        if not passed: failures.append(case)
        summary = dict(case=case, passed=passed, compact_equal=equal, loop_equal=loop_ok,
                       pcm_equal=pcm_ok, slots=sorted(slots), audio=audio)
        summaries.append(summary)
        print(json.dumps(summary))
    (root / f'{args.label}-verification.json').write_text(json.dumps(summaries, indent=2))
    if args.cases:
        found = {s['case'] for s in summaries}
        if found != set(args.cases):
            failures.append(f'Case set mismatch: missing={set(args.cases)-found}, unexpected={found-set(args.cases)}')
        log = (root / f'{args.label}.log').read_text().splitlines()
        if not log or log[-1] != 'DONE' or any(s.startswith(('ERROR\t', 'TIMEOUT\t')) for s in log):
            failures.append('Run did not finish cleanly; inspect log')
    if not summaries or failures:
        raise SystemExit(f'Failed: {failures or "no results"}')


if __name__ == '__main__':
    main()
