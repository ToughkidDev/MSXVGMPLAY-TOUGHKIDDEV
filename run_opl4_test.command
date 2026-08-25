#!/bin/bash
cd "$(dirname "$0")"
openmsx -machine Panasonic_FS-A1GT -ext slotexpander -ext slotexpander -ext ide -ext Yamaha_SFG-05 -ext audio -ext moonsound -ext ram4mb -ext MegaFlashROM_SCC\+ -ext Musical_Memory_Mapper -script openmsx.tcl
