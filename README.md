VGMPlay MSX
===========

This repository is the ToughkidDEV enhanced fork.  It adds a streaming loading
path for large VGM/VGZ files: PCM blocks are sent directly to supported sound
cartridge memory while the much smaller register-command stream remains in MSX
mapper RAM.  This removes the original requirement to keep a complete PCM-rich
VGM image in system memory before playback begins.

Enhanced streaming loader
-------------------------

The original mapped-file loading model needed enough mapper RAM for the whole
VGM, including every PCM/ROM image.  In this fork, the loader performs one
sequential scan before playback:

1. It reads the VGM header and constructs the sound-chip/driver set.
2. It streams plain VGM bytes directly from MSX-DOS, or inflates VGZ input in
   small relay chunks.  A complete decompressed VGZ is never stored in RAM.
3. It diverts cartridge-backed PCM data blocks to the selected device as they
   are read.
4. It appends only VGM register commands, waits, the end marker and data
   blocks that do not have a direct cartridge destination to a compact,
   mapper-backed command buffer.
5. It translates VGM loop offsets to their new positions in that compact
   buffer.  Playback then reads exclusively from memory, so disk access does
   not affect timing.

The following VGM PCM/ROM data-block types are streamed directly when the
corresponding device is connected:

| VGM type | Destination | Typical MSX device |
| --- | --- | --- |
| `0x81` | YM2608 ADPCM | Makoto / OPNA-capable setup |
| `0x82` | YM2610 PCM-A | Neotron |
| `0x83` | YM2610 PCM-B | Neotron |
| `0x84` | YMF278B OPL4 ROM | DalSoRi R2 / compatible OPL4 |
| `0x87` | YMF278B OPL4 RAM | DalSoRi R2 / compatible OPL4 |
| `0x88` | Y8950 ADPCM | MSX-AUDIO |

This does not make system RAM irrelevant: the compact register/wait stream
still uses mapper segments, and unusually command-heavy files can still exceed
the available mapper capacity.  PCM size, however, no longer dominates the
system-memory requirement when it is transferred to cartridge memory.

During loading, VGMPlay displays the PCM destination and compact progress
marks.  Once scanning is complete, it prints the regular track information
and the active VGM-chip-to-MSX-driver mapping before playback.

VGZ implementation notes
------------------------

VGZ support is forward-only.  The inflater temporarily maps two dedicated
16KB segments as its 32KB sliding window, preserves that window across relay
fills, and restores the stream-loader and command-writer pages immediately
after each inflation step.  The command buffer therefore remains usable while
the file is decompressed a chunk at a time.  The temporary segments are owned
by the process and are released by MSX-DOS at program termination.

Testing and openMSX setup
-------------------------

`tools/msx-test` is a reusable MSX-DOS 2/openMSX test kit.  It builds and
deploys the current COM file to the configured disk image, boots the selected
machine, enters a command automatically and stores screenshots/traces outside
version control.  Copy `config.example.sh` to `config.local.sh` and set the
machine, disk image and command for a local setup.

The enhanced streaming path was tested on a Panasonic FS-A1GT MFSCCSD setup
with its native 1.5MB mapper arrangement: 1MB in slot `3-0` and 512KB in slot
`2-2`, with 1,360KB free according to the MSX-DOS memory test.  No `ram4mb`
extension was used for the following results:

| Suite | Sound setup | Result |
| --- | --- | --- |
| MSX-AUDIO/Y8950, 85 VGZ tracks | Generic MSX-AUDIO | 85/85 playback entries |
| Random OPL4 ROM | slot expander + DalSoRi R2 | 15/15 playback entries |
| Random OPL4 RAM | slot expander + DalSoRi R2 | 5/5 playback entries |
| Random YM2610 | slot expander + Neotron | 15/15 playback entries |
| Random YM2608 | Makoto | 15/15 playback entries |

For the automated suites, a pass is accepted only after the CPU reaches the
actual `Application_Play` instruction signature of the compiled VGMPlay COM;
this avoids false positives from an MSX-DOS mapper segment that happens to use
the same numeric address.  A representative MSX-AUDIO run also produced a
non-silent ten-second WAV capture.  These checks establish load, PCM transfer,
device connection and playback entry; they are not a substitute for listening
comparison against a reference recording.

On the validated turboR configuration, the OPL4/DalSoRi R2 and Neotron
extensions require `slotexpander` simply because the machine's cartridge slots
are already occupied.  It does not add mapper RAM.  Typical test invocations
are:

```sh
# Native 1.5MB mapper, YM2608
openmsx -machine Panasonic_FS-A1GT-MFSCCSDv5SFG05 -ext MAKOTO

# Native 1.5MB mapper, YM2610 or OPL4
openmsx -machine Panasonic_FS-A1GT-MFSCCSDv5SFG05 \
  -ext slotexpander -ext NEOTRON
openmsx -machine Panasonic_FS-A1GT-MFSCCSDv5SFG05 \
  -ext slotexpander -ext Jun_Soft_DalSoRi_R2

# Native 1.5MB mapper, MSX-AUDIO
openmsx -machine Panasonic_FS-A1GT-MFSCCSDv5SFG05 -ext audio
```

GitHub builds and releases
--------------------------

Push a version tag beginning with `v` (for example `v1.5.0`) to create a
GitHub Release automatically.  The workflow builds `bin/vgmplay.com` and
`bin/vgmplay.zip`, attaches both files to that release, and generates release
notes from the commits.  Normal pushes and pull requests build the same files
and retain them as workflow artifacts.  The first enhanced release is
[`v1.4.tk1`](https://github.com/ToughkidDev/MSXVGMPLAY-TOUGHKIDDEV/releases/tag/v1.4.tk1).

Large VGM/VGZ music collections and openMSX captures are intentionally not
kept in this source repository.

Copyright 2015 Laurens Holst

Thanks go to l_oliveira, popolon(fr), Pencioner, Supersoniqs and JunSoft for
support.

Project information
-------------------

Plays back VGM music files on MSX with the supported sound chips.

  * Author: Laurens Holst <laurens@grauw.nl>
  * Site: <http://www.grauw.nl/projects/vgmplay-msx/>
  * Source: <https://hg.sr.ht/~grauw/vgmplay-msx>
  * Issues: <https://todo.sr.ht/~grauw/vgmplay-msx>
  * Support: <http://www.msx.org/forum/msx-talk/software/vgmplay-msx>
  * License: Simplified BSD License

VGMPlay can play back music for quite a number of sound chips using various
common and less common sound expansions for MSX, such as the PSG, MoonSound and
Yamaha SFG. A detailed list can be found below.

Both the VGM and VGZ formats are supported. The compressed VGZ format takes
longer to load but also consumes less disk space. If so desired, VGZ files can
be manually decompressed to VGM with
[gunzip for MSX](http://www.grauw.nl/projects/gunzip/) or PC.

The timing resolution is 50 or 60 Hz on MSX1 machines with a TMS9918 VDP, 300 Hz
on machines with a V9938 or V9958 VDP, 1130 Hz if a MoonSound or OPL3 is
present, and 4000 Hz on MSX turboR.

For collections of VGM music see:

  * <http://vgmrips.net/>
  * <http://www.smspower.org/Music/VGMs>
  * <http://opl.wafflenet.com/>


System requirements
-------------------

  * MSX, MSX2, MSX2+ or MSX turboR
  * 128K main RAM
  * 16K video RAM
  * MSX-DOS 2


Supported sound chips
---------------------

  * AY-3-8910 PSG / YM2149 SSG x2
    * Internal PSG, Darky, MegaFlashROM SCC+
  * YM2151 OPM x2
    * Yamaha SFG
  * YM2413 OPLL
    * MSX-MUSIC, FM-PAC
  * YM3526 OPL x2
    * MSX-AUDIO, Music Module, MoonSound, OPL3
  * YM3812 OPL2 x2
    * MoonSound, OPL3
  * YMF262 OPL3 x2
    * MoonSound, OPL3
  * YMF278B OPL4
    * MoonSound, DalSoRi R2 (4MB mode)
  * Y8950 MSX-AUDIO x2
    * MSX-AUDIO, Music Module, MoonSound (no ADPCM), OPL3 (no ADPCM)
  * K051649 Konami SCC
    * Konami SCC, Konami Sound Cartridge
  * K052539 Konami SCC+
    * Konami Sound Cartridge
  * SN76489 DCSG x2
    * Musical Memory Mapper, Playsoniq, Franky, PSG
  * YM2203 OPN x2
    * Makoto, Neotron, Yamaha SFG + PSG
  * YM2608 OPNA
    * Makoto, Yamaha SFG + PSG + MSX-AUDIO (no drums)
  * YM2610 OPNB
    * Neotron
  * YM2610B OPNB-B
    * Neotron + Makoto
  * YM2612 OPN2 x2
    * Makoto + turboR PCM, Yamaha SFG + turboR PCM
  * SAA1099
    * SoundStar


Usage instructions
------------------

Run VGMPlay from MSX-DOS 2, specifying the VGM file to play on the command line.

Usage:

    vgmplay [options] <file.vgm>

The compressed VGZ format is also supported.

Options:

  * `/l` Number of playback loops. Default: 2.
    
    Many VGM music loops once the end of the song is reached. With this setting
    you can specify how many times VGMPlay should play the repeating part before
    exiting. The amount is specified like `/L15`. Use `/L` or `/L0` to loop
    infinitely. This setting will have no effect for songs which don’t loop.
    
  * `/b` Enter blackout mode during playback.
    
    This setting makes the screen go black during playback. For machines with a
    lot of VDP interference on the audio output, this may reduce the amount of
    interference.

To configure Multi Mente to play VGM files, add the following lines to
MMRET.DAT:

    .VGM    VGMPLAY $T
    .VGZ    VGMPLAY $T


Development information
-----------------------

VGMPlay is free and open source software. If you want to contribute to the
project you are very welcome to. Please contact me at any one of the places
mentioned in the project information section.

You are also free to re-use code for your own projects, provided you abide by
the license terms.

The GitHub repository vendors the Neonlib and Gunzip source trees needed by
the Makefile, so a normal Git clone builds without Mercurial subrepository
setup.

Building the project is easy on all modern desktop platforms. On MacOS and
Linux, simply invoke `make` to build the binary and symbol files into the
`bin` directory:

    make

Windows users can open the `Makefile` and build by pasting the line in the `all`
target into the Windows command prompt.

To launch the build in openMSX after building, put a copy of `MSXDOS2.SYS` and
`COMMAND2.COM` and some VGM files to test with in the `bin` directory, and then
invoke the `make run` command.

Note that the [glass](http://www.grauw.nl/projects/glass/) assembler which is
embedded in the project requires [Java 8](http://java.com/getjava). To check
your Java version, invoke the `java -version` command.
