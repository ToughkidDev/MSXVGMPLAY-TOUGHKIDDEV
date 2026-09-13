# Load-time benchmark using emulated seconds, not host/throttle timing.
# BENCH_SYMBOLS, BENCH_COM, BENCH_LABEL, BENCH_CASES, BENCH_OUTPUT are required.
set throttle off
set ::bench_output $::env(BENCH_OUTPUT)
set ::bench_label $::env(BENCH_LABEL)
set ::bench_program $::bench_label
if {[info exists ::env(BENCH_PROGRAM)]} {set ::bench_program $::env(BENCH_PROGRAM)}
set ::bench_cases $::env(BENCH_CASES)
set ::bench_index 0
set ::bench_state idle
set ::bench_started 0
set ::bench_bps {}
array set ::bench_symbols {}
set f [open $::env(BENCH_SYMBOLS) r]
foreach line [split [read $f] \n] {
    if {[regexp {^([^:]+): equ ([0-9A-F]+)H$} $line -> name hex]} {
        scan $hex %x ::bench_symbols($name)
    }
}
close $f
set f [open $::env(BENCH_COM) rb]
set ::bench_binary [read $f]
close $f

proc bench_log {s} {
    puts $s
    set f [open "$::bench_output/$::bench_label.log" a]
    puts $f $s
    close $f
}
proc bench_valid {name} {
    set addr $::bench_symbols($name)
    set expected [string range $::bench_binary [expr {$addr - 256}] [expr {$addr - 256 + 11}]]
    return [expr {[debug read_block memory $addr 12] eq $expected}]
}
proc bench_start {} {
    if {$::bench_state ne "waiting"} return
    set ::bench_started [machine_info time]
    set ::bench_state loading
    set ::bench_pcm {}
    bench_log "START\t$::bench_case\t$::bench_started"
}
proc bench_word {addr} {
    return [expr {[debug read memory $addr] | ([debug read memory [expr {$addr+1}]] << 8)}]
}
proc bench_play {} {
    if {$::bench_state ne "loading"} return
    set elapsed [expr {[machine_info time] - $::bench_started}]
    set ::bench_state playing
    bench_log "PLAY\t$::bench_case\t$elapsed"
    if {[info exists ::env(BENCH_PCM)]} {
        set f [open "$::bench_output/$::bench_label-$::bench_case.pcm" wb]
        puts -nonewline $f $::bench_pcm
        close $f
    }
    set sizeaddr $::bench_symbols(MappedBuffer_instance.size)
    set size [expr {[bench_word $sizeaddr] | ([bench_word [expr {$sizeaddr+2}]] << 16)}]
    set count [bench_word $::bench_symbols(MappedBuffer_instance.segmentCount)]
    set table $::bench_symbols(MappedBuffer_instance.segments)
    set header [bench_word $::bench_symbols(Application_instance.streamLoader.header)]
    set loopaddr [expr {$header + 0x1c}]
    set loop [expr {[bench_word $loopaddr] | ([bench_word [expr {$loopaddr+2}]] << 16)}]
    set f [open "$::bench_output/$::bench_label-$::bench_case.segments" w]
    puts $f "size=$size count=$count loop=$loop"
    for {set i 0} {$i < $count} {incr i} {
        set segment [debug read memory [expr {$table + $i*2}]]
        set slot [debug read memory [expr {$table + $i*2+1}]]
        puts $f "$segment $slot"
    }
    close $f
    # Physical RAM dumps let the host verify every compact byte without
    # disturbing the program's current page mappings or registers.
    foreach name [debug list] {
        if {$name in {"Main RAM" "MegaFlashRom SCC+ SD memory mapper"}} {
            if {[catch {set n [debug size $name]}]} continue
            if {$n < 16384 || $n > 4194304} continue
            set f [open "$::bench_output/$::bench_label-$::bench_case.[string map {" " _ "/" _} $name].ram" wb]
            puts -nonewline $f [debug read_block $name 0 $n]
            close $f
        }
    }
    if {[info exists ::env(BENCH_AUDIO)]} {
        soundlog start "$::bench_output/$::bench_label-$::bench_case.wav"
    }
    after time 5 bench_capture
}
proc bench_sios {} {
    if {$::bench_state ne "loading"} return
    set slot [debug read memory $::bench_symbols(Neotron_instance.slot)]
    if {![pc_in_slot [expr {$slot & 3}] [expr {($slot >> 2) & 3}]]} return
    set count [expr {[reg BC] & 0xff00}]
    append ::bench_pcm [binary format ccc [reg A] [expr {$count & 255}] [expr {$count >> 8}]]
    append ::bench_pcm [debug read_block memory [reg HL] $count]
}
proc bench_capture {} {
    if {[info exists ::env(BENCH_AUDIO)]} {soundlog stop}
    screenshot "$::bench_output/$::bench_label-$::bench_case.png"
    bench_log "RUN\t$::bench_case\tPC=[format %04X [reg PC]]"
    type_via_keybuf " "
    set ::bench_state stopping
    after time 4 bench_next
}
proc bench_error {} {
    if {$::bench_state ne "loading"} return
    set ::bench_state failed
    bench_log "ERROR\t$::bench_case\tPC=[format %04X [reg PC]]"
    after time 1 {
        screenshot "$::bench_output/$::bench_label-$::bench_case-error.png"
        bench_next
    }
}
proc bench_next {} {
    if {$::bench_index >= [llength $::bench_cases]} {bench_log DONE; exit}
    set ::bench_case [lindex $::bench_cases $::bench_index]
    incr ::bench_index
    set ::bench_state waiting
    type_via_keybuf "c:\\ntrbench\\$::bench_program /l1 c:\\ntrbench\\$::bench_case\r"
}
proc bench_timeout {} {
    if {$::bench_state in {waiting loading}} {
        screenshot "$::bench_output/$::bench_label-$::bench_case-timeout.png"
        bench_log "TIMEOUT\t$::bench_case\tPC=[format %04X [reg PC]]"
        exit
    }
    after time 1800 bench_timeout
}
foreach name {Application_StreamLoadVGZ Application_StreamLoadVGM} {
    lappend ::bench_bps [debug set_bp $::bench_symbols($name) "\[bench_valid $name\]" bench_start]
}
lappend ::bench_bps [debug set_bp $::bench_symbols(Application_Play) {[bench_valid Application_Play]} bench_play]
foreach name {System_ThrowException System_ThrowExceptionWithMessage} {
    lappend ::bench_bps [debug set_bp $::bench_symbols($name) "\[bench_valid $name\]" bench_error]
}
if {[info exists ::env(BENCH_PCM)]} {
    debug set_bp 0x8025 {} bench_sios
}
after time 129 {bench_log "DEVICES\t[debug list]"}
after time 130 bench_next
after time 1930 bench_timeout
