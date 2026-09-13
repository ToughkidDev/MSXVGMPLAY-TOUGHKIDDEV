#!/usr/bin/env python3
"""Prepare bounded, reproducible Neotron cases and reference compact streams."""
import argparse
import gzip
import hashlib
import json
import struct
import zlib
from pathlib import Path


def compact(data):
    u32 = lambda p: struct.unpack_from('<I', data, p)[0]
    start = 0x34 + u32(0x34) if u32(8) >= 0x150 and u32(0x34) else 0x40
    loop = 0x1c + u32(0x1c) if u32(0x1c) else None
    out = bytearray(64)
    blocks = []
    loop_out = None
    p = start
    while p < len(data):
        if p == loop:
            loop_out = len(out)
        op = data[p]
        if op == 0x66:
            out.append(op)
            return bytes(out), blocks, loop_out
        if op == 0x67:
            assert data[p + 1] == 0x66
            n = u32(p + 3) & 0x7fffffff
            end = p + 7 + n
            assert end <= len(data)
            kind = data[p + 2]
            if kind in (0x81, 0x82, 0x83, 0x84, 0x87, 0x88):
                blocks.append({'type': hex(kind), 'size': n, 'start': u32(p + 11) if n >= 8 else None, 'dataOffset': p+15})
            else:
                out.extend(data[p:end])
        else:
            if op < 0x30: n = 0
            elif op < 0x40: n = 1
            elif op < 0x4f: n = 2
            elif op < 0x51: n = 1
            elif op < 0x60: n = 2
            elif op == 0x61: n = 2
            elif op in (0x62, 0x63): n = 0
            elif op == 0x68: n = 11
            elif 0x70 <= op <= 0x8f: n = 0
            elif op in (0x90, 0x91, 0x95): n = 4
            elif op == 0x92: n = 5
            elif op == 0x93: n = 10
            elif op == 0x94: n = 1
            elif 0xa0 <= op <= 0xbf: n = 2
            elif 0xc0 <= op <= 0xdf: n = 3
            elif op >= 0xe0: n = 4
            else: raise ValueError(f'Unsupported opcode {op:02x} at {p:x}')
            end = p + 1 + n
            out.extend(data[p:end])
        p = end
    raise ValueError('No end marker')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    paths = [
        'metalslg/1Metal_Slug_(Neo_Geo)/04 Boss Stage.vgz',
        'metalslg/1Metal_Slug_(Neo_Geo)/06 Stage 2.vgz',
        'metalslg/2Metal_Slug_2_(SNK_Neo_Geo)/16 Final Attack.vgz',
        'SamSho3/sm3endfo.vgm',
        'deflemask/defledemo.vgm',
    ]
    manifest = []
    inputs = [(rel, (args.root / rel).read_bytes()) for rel in paths]
    def fixture(commands, offset=0x80, loop=None):
        header = bytearray(offset)
        header[:4] = b'Vgm '
        for pos, value in [(8, 0x171), (0x34, offset-0x34),
                           (0x4c, 0x807a1200), (0x18, 441000)]:
            struct.pack_into('<I', header, pos, value)
        if loop is not None:
            struct.pack_into('<I', header, 0x1c, offset + loop - 0x1c)
            struct.pack_into('<I', header, 0x20, 220500)
        result = header + commands + b'\x66'
        struct.pack_into('<I', result, 4, len(result) - 4)
        return bytes(result)
    def block(kind, size):
        payload = bytes(i % 251 for i in range(size))
        return b'\x67\x66' + bytes([kind]) + struct.pack('<III', size+8, 65536, 0) + payload
    # Spill command storage into the secondary mapper and exercise loop offsets.
    inputs.append(('fixture: secondary mapper', fixture(b'\x70' * 950003, loop=475001)))
    # A tail shorter than one SIOS page must not consume the next command.
    tails = b''.join(block(k, n) + b'\x58\x22\x00'
                     for k in (0x82, 0x83) for n in (1, 255, 257))
    inputs.append(('fixture: PCM tails', fixture(tails + b'\x61\xff\xff' * 10)))
    # End-of-stream padding plus short stored/fixed/dynamic deflate boundaries.
    mixed = fixture(b'\x70' * 777 + b'\x58\x22\x00' * 351 + b'\x61\xff\xff' * 10)
    compressor = zlib.compressobj(wbits=31)
    zipped = compressor.compress(mixed[:350]) + compressor.flush(zlib.Z_SYNC_FLUSH)
    zipped += compressor.compress(mixed[350:900]) + compressor.flush(zlib.Z_FULL_FLUSH)
    zipped += compressor.compress(mixed[900:]) + compressor.flush()
    inputs.append(('fixture: gzip flush boundaries', zipped))
    for rel in [
        'ym2610_Neogeo/Strikers_1945_Plus_(Neo_Geo)/12 Mission 5.vgz',
        'ym2610_Neogeo/Rage_of_The_Dragons_(Neo_Geo)/23 Glorious Heart (Credit Roll).vgz',
        'ym2610_Neogeo/Neo_Turf_Masters_(Neo_Geo)/10 Grand Canyon Golf Course - U.S.A..vgz',
    ]:
        inputs.append((rel, (args.root / rel).read_bytes()))
    for i, (rel, raw) in enumerate(inputs, 1):
        data = gzip.decompress(raw) if raw[:2] == b'\x1f\x8b' else raw
        expected, blocks, loop = compact(data)
        name = f'T{i:02d}'
        (args.output / f'{name}.VGM').write_bytes(data)
        (args.output / f'{name}.VGZ').write_bytes(raw if raw[:2] == b'\x1f\x8b' else gzip.compress(data, mtime=0))
        (args.output / f'{name}.expected').write_bytes(expected)
        manifest.append(dict(name=name, source=rel, expanded=len(data), compact=len(expected),
                             sha256=hashlib.sha256(expected).hexdigest(), loop=loop, blocks=blocks))
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    for r in manifest:
        print(r['name'], r['source'], 'expanded', r['expanded'], 'compact', r['compact'],
              'PCM', sum(b['size'] - 8 for b in r['blocks']),
              'unaligned', [b for b in r['blocks'] if (b['size'] - 8) % 256])


if __name__ == '__main__':
    main()
