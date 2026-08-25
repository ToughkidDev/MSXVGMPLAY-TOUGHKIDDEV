# Generic non-interactive openMSX smoke runner.  Values arrive from
# run-smoke.sh so this file remains portable across MSX projects.
set throttle off
set boot_seconds $::env(MSX_TEST_BOOT_SECONDS)
set run_seconds $::env(MSX_TEST_RUN_SECONDS)
set artifact_dir $::env(MSX_TEST_ARTIFACT_DIR)
set command $::env(MSX_TEST_COMMAND)

proc smoke_capture {artifact_dir} {
  screenshot "$artifact_dir/smoke.png"
  set trace [open "$artifact_dir/smoke.txt" w]
  puts $trace "PC=[format %04X [reg PC]] SP=[format %04X [reg SP]] AF=[format %04X [reg AF]] BC=[format %04X [reg BC]] DE=[format %04X [reg DE]] HL=[format %04X [reg HL]] IX=[format %04X [reg IX]] IY=[format %04X [reg IY]]"
  close $trace
  exit
}

after time $boot_seconds [list type_via_keybuf "${command}\r"]
after time $run_seconds [list smoke_capture $artifact_dir]
