# MSX/openMSX reusable test kit

This kit keeps the emulator setup, DOS2 boot target, disk-image deployment,
automatic command entry, screenshot capture, and register snapshot in one
place.  It is deliberately independent of VGMPlay: copy `tools/msx-test` into
another MSX project and update only `config.local.sh`.

## One-time setup

```sh
cp tools/msx-test/config.example.sh tools/msx-test/config.local.sh
```

Set these values in `config.local.sh`:

- `MSX_TEST_MACHINE`: openMSX machine name.  The validated current value is
  `Panasonic_FS-A1GT-MFSCCSDv5SFG05`, which boots MSX-DOS 2 from SCC+ SD.
- `MSX_TEST_OPENMSX_ARGS`: optional extension arguments. On the validated
  turboR machine, OPL4/DalSoRi R2 and Neotron need the slot expander:
  `(-ext slotexpander -ext ram4mb -ext Jun_Soft_DalSoRi_R2)` or
  `(-ext slotexpander -ext ram4mb -ext NEOTRON)`.  Makoto YM2608 fits directly:
  `(-ext ram4mb -ext MAKOTO)`.
- `MSX_TEST_DISK_IMAGE`: persistent SD/disk image to receive the test COM.
- `MSX_TEST_INSTALL_DESTINATION`: MSX-DOS path for the test program.
- `MSX_TEST_COMMAND`: command to type after boot, including the target VGM/VGZ.

`config.local.sh` and generated screenshots/traces are intentionally ignored
by Mercurial, so machine-specific paths and media do not enter source control.

## Normal loop

```sh
bash tools/msx-test/install-current-build.sh
bash tools/msx-test/run-smoke.sh
```

The smoke runner saves `artifacts/smoke.png` and `artifacts/smoke.txt`.
It does not alter the music files or any disk content other than the explicit
test program destination configured above.

## Debugging

Copy `smoke.tcl` to a project-specific Tcl file and add `debug set_bp` or
`debug set_watchpoint` commands.  Keep generic boot, command, screenshot and
trace handling in `smoke.tcl`; this avoids rebuilding an openMSX harness for
each bug.  `openmsx.tcl` at the repository root remains available for the
older symbol/profile workflow.
