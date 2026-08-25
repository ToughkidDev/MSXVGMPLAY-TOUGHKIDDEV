;
; PCM block loading progress display.
;
; While a PCM data block is streamed from disk straight into a chip's own
; memory (OPL4 wave RAM, Neotron sample memory, YM2608/Y8950 ADPCM RAM), this
; prints the destination name once, then a "." for every fixed-size chunk
; that has been transferred, so the user gets visual feedback during long
; loads. StreamLoader_DispatchDataBlock calls Progress_StartBlock right
; before handing off to the chip's own ProcessXXXDataBlock routine, and
; Progress_EndBlock right after it returns. Each driver's own transfer loop
; calls Progress_Update once per chunk actually read from the Reader.
;
Progress_THRESHOLD: equ 1000H  ; bytes per "."

Progress_counter:
	dw 0
Progress_name:
	dw 0

; hl = block destination name (0-terminated)
; Modifies: none
Progress_StartBlock: PROC
	push af
	ld a,(Progress_name)
	cp l
	jr nz,NewBlockType
	ld a,(Progress_name + 1)
	cp h
	jr z,Done
NewBlockType:
	call Progress_Finish
	ld a,l
	ld (Progress_name),a
	ld a,h
	ld (Progress_name + 1),a
	xor a
	ld (Progress_counter),a
	ld (Progress_counter + 1),a
	call System_Print
	ld a,':'
	call System_PrintChar
	ld a,' '
	call System_PrintChar
Done:
	pop af
	ret
	ENDP

; A VGM may split one PCM image into hundreds of adjacent data blocks. Keep
; such an image on a single progress line; StreamLoader finishes that line at
; the end of its complete scan.
; Modifies: none
Progress_EndBlock: equ System_Return

; Modifies: none
Progress_Finish: PROC
	push af
	push hl
	ld a,(Progress_name)
	or a
	jr nz,Active
	ld a,(Progress_name + 1)
	or a
	jr z,Done
Active:
	call System_PrintCrLf
	xor a
	ld (Progress_name),a
	ld (Progress_name + 1),a
Done:
	pop hl
	pop af
	ret
	ENDP

; bc = bytes just transferred in this chunk
; Modifies: none
Progress_Update: PROC
	push af
	push de
	push hl
	ld hl,(Progress_counter)
	add hl,bc
Loop:
	ld de,-Progress_THRESHOLD
	add hl,de
	jr c,Done
	ld a,'.'
	call System_PrintChar
	jr Loop
Done:
	ld de,Progress_THRESHOLD
	add hl,de
	ld (Progress_counter),hl
	pop hl
	pop de
	pop af
	ret
	ENDP
