# Neotron streaming regression and loading benchmark

Date: 2026-09-13. Baseline: git `1a8eef0` (v1.4.tk2). These optimizations
are included in v1.4.tk3. The measured build retained the v1.4.tk2 banner;
release preparation changes that banner to v1.4.tk3 without changing code.

## Environment and scope

- Executable: `/Applications/_openMSX/openMSXTK.app/Contents/MacOS/openmsx`.
- Machine: `Panasonic_FS-A1GT-MFSCCSDv5SFG05`, booting MSX-DOS 2.
- Extensions: `-ext slotexpander -ext NEOTRON`. **No `ram4mb`.**
- Mapper RAM: 1MB in slot 3-0 plus 512KB in slot 2-2, approximately 1360KB
  free before starting VGMPlay. The synthetic spill test used both mappers.
- Music root: the user-supplied `_Playgrnd/testVGMFiles/NeoTron` directory.
  Eight real tracks were selected; this was not an exhaustive directory test.
- Dedicated DOS test directory: `C:\NTRBENCH`. Source music is not modified.
- Timing: `machine_info time`, from `Application_StreamLoadVGM/VGZ` to
  `Application_Play`, with host throttling disabled. Values are emulated
  seconds, not host elapsed time or real-hardware measurements.

## Loading results

| Track / input | Baseline (s) | Optimized (s) | Reduction |
| --- | ---: | ---: | ---: |
| Metal Slug — 04 Boss Stage / VGZ | 94.597 | 88.998 | 5.9% |
| Metal Slug — 06 Stage 2 / VGZ | 118.026 | 108.034 | 8.5% |
| Metal Slug 2 — 16 Final Attack / VGZ | 165.860 | 149.302 | 10.0% |
| Samurai Shodown III — sm3endfo / VGM | 52.240 | 40.950 | 21.6% |
| DefleMask — defledemo / VGM | 42.432 | 32.931 | 22.4% |

These are single-run observations, not statistical averages. Test ordering
and retained machine state can vary slightly: a second baseline Boss Stage
load took 95.122s. A relay-only intermediate build reduced the three VGZ
loads to 91.539s, 114.397s and 161.178s. The additional short-command and
same-slot paths provided the remaining improvement.

## Correctness evidence

Final Neotron run: **15/15 cases passed**. Each case reached playback and
was observed for approximately five emulated seconds. Verification compares
the complete compact command buffer against a host-generated reference,
the translated loop offset, and the complete PCM write-payload transcript
passed to the Neotron SIOS entry point. PCM-A and PCM-B identifiers and
zero-padded final pages are included in that comparison. This does not
independently read back the cartridge ROM or verify every write address.

| Case | Source / property | Tested inputs | PCM payload bytes | Compact bytes |
| --- | --- | --- | ---: | ---: |
| T01 | Metal Slug — 04 Boss Stage | VGM, VGZ | 2,192,128 | 132,980 |
| T02 | Metal Slug — 06 Stage 2 | VGZ | 2,542,080 | 274,114 |
| T03 | Metal Slug 2 — 16 Final Attack | VGZ | 3,168,000 | 534,513 |
| T04 | SamSho3/sm3endfo | VGM, VGZ | 446,464 | 583,024 |
| T05 | deflemask/defledemo | VGM, VGZ | 313,088 | 523,616 |
| T06 | Synthetic commands spilling into secondary mapper | VGZ | 0 | 950,068 |
| T07 | Synthetic PCM-A/B tails of 1, 255 and 257 bytes | VGM, VGZ | 1,026 | 113 |
| T08 | Synthetic gzip flush boundaries, partial final relay | VGZ | 0 | 1,925 |
| T09 | Strikers 1945 Plus — 12 Mission 5 | VGZ | 1,862,656 | 344 |
| T10 | Rage of the Dragons — 23 Glorious Heart | VGZ | 1,609,472 | 528 |
| T11 | Neo Turf Masters — 10 Grand Canyon Golf Course | VGZ | 1,589,248 | 433,536 |

All 11 real-track/input combinations produced non-silent five-second WAVs
(RMS 329–1301 in signed 16-bit sample units). Synthetic fixtures are silent
by design. Captures and GD3/chip-info screenshots are retained locally.
This proves initial output, not full-song musical fidelity or loop playback.

Baseline T07 VGM and VGZ both raised an exception. The optimized versions
both pass: the last read is now limited to the actual PCM bytes remaining,
with only the local 256-byte SIOS write buffer padded. Subsequent commands
are no longer consumed as PCM.

A second run without `NEOTRON` passed **2/2** cases (T01.VGZ, T07.VGZ),
including complete compact-stream and loop-offset checks. No cartridge
PCM transcript or audio assertion is made for this missing-device run.

## Changes and memory budget

- Decoded relay: 256B to 1KB; compressed input: 2816B to 2KB. Combined
  buffer allocation remains 3KB. The 32KB DEFLATE history is retained.
- Reposition inside the first decoded relay for data offsets below 256;
  do not discard prefetched commands or rebuild a separate header replay.
- Use the full 16-bit destination when accumulating partial inflate slices.
- Skip redundant slot selection for same-mapper page changes. Still change
  mapper segments and retain the full cross-slot path.
- Use a short-copy command writer for 1–11 bytes that fit the current page.
- Fix Neotron partial PCM reads and the inverted 4KB progress carry test.

No Makoto ADPCM naming/display changes were made. Other chip extensions
were not rerun in this specific optimization pass; shared-loader regression
on Makoto/OPL4 and full-song/loop listening remain useful follow-up coverage.
Further performance work could batch small commands before mapper writes
or profile the inflater itself; neither change is included here.

## Reusing the test

`prepare-neotron-bench.py MUSIC_ROOT OUTPUT_DIR` creates the manifest,
reference compact buffers, music copies and synthetic fixtures. Its fixed
track list requires this source collection. Generated music and recordings
belong under ignored `artifacts/`, not in source control.

Build with `make all`. Save the COM and matching symbols together, and copy
the COM as `C:\NTRBENCH\OPT.COM` and required Txx input files into the same
DOS directory. Stop all emulators accessing the SD image before using
`mcopy`; use the existing DOS2 image rather than rebuilding the environment.

Launch openMSXTK with the machine/extensions above and
`-script tools/msx-test/neotron-bench.tcl`. Supply these environment variables:

- `BENCH_SYMBOLS`: absolute path to that build's `vgmplay.sym`.
- `BENCH_COM`: absolute path to the matching COM.
- `BENCH_LABEL`: output filename prefix; use a fresh label for each run.
- `BENCH_PROGRAM`: DOS executable basename, defaulting to `BENCH_LABEL`.
- `BENCH_OUTPUT`: absolute output directory containing the manifest.
- `BENCH_CASES`: space-separated DOS filenames.
- `BENCH_AUDIO=1`: record approximately five seconds after playback starts.
- `BENCH_PCM=1`: capture SIOS payloads; use only with Neotron attached.

For the final suite, `BENCH_PROGRAM=OPT` and `BENCH_CASES` were:

```text
T07.VGM T07.VGZ T08.VGZ T06.VGZ T01.VGZ T02.VGZ T03.VGZ T04.VGM T05.VGM T01.VGM T04.VGZ T05.VGZ T09.VGZ T10.VGZ T11.VGZ
```

Verify after the emulator exits:

```sh
python3 tools/msx-test/verify-neotron-bench.py \
  tools/msx-test/artifacts/neotron-perf OPT --require-pcm --require-audio \
  --cases T07.VGM T07.VGZ T08.VGZ T06.VGZ T01.VGZ T02.VGZ T03.VGZ \
  T04.VGM T05.VGM T01.VGM T04.VGZ T05.VGZ T09.VGZ T10.VGZ T11.VGZ
```

The verifier checks case completeness and clean termination when `--cases`
is supplied. It assumes the two mapper-slot IDs of this reference machine.
For the missing-device test, omit `-ext NEOTRON`, `BENCH_PCM` and
`BENCH_AUDIO`, set `BENCH_LABEL=SKIP`, and verify T01.VGZ and T07.VGZ.

Artifacts: `tools/msx-test/artifacts/neotron-perf/`, including `.log`, `.png`,
`.wav`, physical `.ram` dumps, `.segments`, `.pcm`, and verification JSON.
Measured pre-release COM SHA-256 (before the banner-only release edit):
`f86f8219097b38cdbc35295513ba3a63621ffa006c32a17c0d5ec951048d2f79`.
