;
; CRC32 summer
;
CRC32Checker: MACRO
	crc32:
		dd 0FFFFFFFFH
	_size:
	ENDM

	IF GZIP_CRC32

; ix = this
; ix <- this
CRC32Checker_Construct:
	ld a,0FFH
	ld (ix + CRC32Checker.crc32),a
	ld (ix + CRC32Checker.crc32 + 1),a
	ld (ix + CRC32Checker.crc32 + 2),a
	ld (ix + CRC32Checker.crc32 + 3),a
	ret

; de = read address
; hl = byte count
; ix = this
CRC32Checker_UpdateCRC32:
	ld a,l
	or h
	ret z
	exx
	ld e,(ix + CRC32Checker.crc32)
	ld d,(ix + CRC32Checker.crc32 + 1)
	ld c,(ix + CRC32Checker.crc32 + 2)
	ld b,(ix + CRC32Checker.crc32 + 3)
	exx
	call CRC32Checker_CalculateCRC32
	exx
	ld (ix + CRC32Checker.crc32),e
	ld (ix + CRC32Checker.crc32 + 1),d
	ld (ix + CRC32Checker.crc32 + 2),c
	ld (ix + CRC32Checker.crc32 + 3),b
	exx
	ret

; bcde = expected crc32
; ix = this
; f <- nz: mismatch
; Modifies: a
CRC32Checker_VerifyCRC32:
	scf
	ld a,e
	adc a,(ix + CRC32Checker.crc32)
	ret nz
	ld a,d
	adc a,(ix + CRC32Checker.crc32 + 1)
	ret nz
	ld a,c
	adc a,(ix + CRC32Checker.crc32 + 2)
	ret nz
	ld a,b
	adc a,(ix + CRC32Checker.crc32 + 3)
	ret

; de = read address
; hl = byte count
; bcde' = current crc32
; ix = this
; bcde' <- updated crc32
CRC32Checker_CalculateCRC32: PROC
	ld b,l  ; convert 16-bit counter bc to two 8-bit counters in b and c
	dec hl
	inc h
Loop:
	ld a,(de)
	inc de
	exx
	xor e
	ld l,a
	ld h,CRC32Table >> 8
	ld a,(hl)
	xor d
	ld e,a
	inc h
	ld a,(hl)
	xor c
	ld d,a
	inc h
	ld a,(hl)
	xor b
	ld c,a
	inc h
	ld b,(hl)
	exx
	djnz Loop
	dec h
	jp nz,Loop
	ret
	ENDP

	ENDIF
