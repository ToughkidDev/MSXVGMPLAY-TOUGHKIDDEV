;
; Adler32 summer
;
Adler32Checker: MACRO
	adler32:
		dd 1
	_size:
	ENDM

	IF ZLIB_ADLER32

; ix = this
; ix <- this
; Modifies: a
Adler32Checker_Construct:
	xor a
	ld (ix + Adler32Checker.adler32),1
	ld (ix + Adler32Checker.adler32 + 1),a
	ld (ix + Adler32Checker.adler32 + 2),a
	ld (ix + Adler32Checker.adler32 + 3),a
	ret

; de = read address
; hl = byte count
; ix = this
Adler32Checker_UpdateAdler32:
	ld a,l
	or h
	ret z
	exx
	ld e,(ix + Adler32Checker.adler32)
	ld d,(ix + Adler32Checker.adler32 + 1)
	ld c,(ix + Adler32Checker.adler32 + 2)
	ld b,(ix + Adler32Checker.adler32 + 3)
	exx
	call Adler32Checker_CalculateAdler32
	exx
	ld (ix + Adler32Checker.adler32),e
	ld (ix + Adler32Checker.adler32 + 1),d
	ld (ix + Adler32Checker.adler32 + 2),c
	ld (ix + Adler32Checker.adler32 + 3),b
	exx
	ret

; bcde = expected adler32
; ix = this
; f <- nz: mismatch
Adler32Checker_VerifyAdler32:
	ld a,e
	sub (ix + Adler32Checker.adler32)
	ret nz
	ld a,d
	sub (ix + Adler32Checker.adler32 + 1)
	ret nz
	ld a,c
	sub (ix + Adler32Checker.adler32 + 2)
	ret nz
	ld a,b
	sub (ix + Adler32Checker.adler32 + 3)
	ret

; de = read address
; hl = byte count
; bcde' = current adler32
; ix = this
; bcde' <- updated adler32
Adler32Checker_CalculateAdler32: PROC
	ld b,l  ; convert 16-bit counter bc to two 8-bit counters in b and c
	dec hl
	inc h
Loop:
	ld a,(de)
	inc de
	exx
	ld l,a
	ld h,0
	AddModulo hl, de, 65521
	ld e,l
	ld d,h
	AddModulo hl, bc, 65521
	ld c,l
	ld b,h
	exx
	djnz Loop
	dec h
	jp nz,Loop
	ret
	ENDP

; ?hl = addend (< ?modulo)
; ?de = addend (< ?modulo)
; ?modulo = modulo value
; Modifies: ?de
AddModulo: MACRO ?hl, ?de, ?modulo
	add ?hl,?de
	ld ?de,10000H - ?modulo
	jp nc,Check
	add ?hl,?de
	jp Done
Check:
	add ?hl,?de
	jr c,Done
	sbc ?hl,?de
Done:
	ENDM

	ENDIF
