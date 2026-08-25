# Copy to config.local.sh and adjust for the current host and project.

MSX_TEST_OPENMSX="/opt/homebrew/bin/openmsx"
MSX_TEST_MACHINE="Panasonic_FS-A1GT-MFSCCSDv5SFG05"

# Optional openMSX command-line arguments for project-specific hardware.
# DalSoRi R2 and Neotron need the slot expander on this turboR machine:
# MSX_TEST_OPENMSX_ARGS=(-ext slotexpander -ext ram4mb -ext Jun_Soft_DalSoRi_R2)
# Makoto YM2608 fits directly and is tested as:
# MSX_TEST_OPENMSX_ARGS=(-ext ram4mb -ext MAKOTO)
MSX_TEST_OPENMSX_ARGS=()

# Persistent image used by the selected openMSX machine.  Leave empty until
# you have chosen an image; the install script refuses to run without it.
MSX_TEST_DISK_IMAGE=""
MSX_TEST_INSTALL_DESTINATION="::VGMTEST/VGMPLAY.COM"

# Command entered after DOS is ready.  Use MSX-DOS 8.3 names where needed.
MSX_TEST_COMMAND="c:\\vgmtest\\vgmplay c:\\path\\to\\test.vgz"
MSX_TEST_BOOT_SECONDS=130
MSX_TEST_RUN_SECONDS=240
