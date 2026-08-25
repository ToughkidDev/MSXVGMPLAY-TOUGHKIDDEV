;
; Zlib archive
;
ZlibArchive_STATE_CHECKSUM_BIT: equ 0
ZlibArchive_STATE_FOOTER_BIT: equ 1
ZlibArchive_DEFLATE_ID: equ 8
ZlibArchive_MAX_WINDOW: equ 7

ZlibArchive: MACRO
	state:
		db 0
	reader:
		dw 0
	cm:
		db 0
	cinfo:
		dd 0
	flevel:
		dd 0
	adler32:
		IF ZLIB_ADLER32
		dd 0
		ENDIF
	inflate:
		Inflate
	adler32Checker:
		IF ZLIB_ADLER32
		Adler32Checker
		ENDIF
	_size:
	ENDM

; a = -1: Adler32 check enabled, 0: disabled
; bc = decoders buffer
; de = write buffer (32K, 256-byte aligned)
; hl = reader
; ix = this
; ix <- this
ZlibArchive_Construct:
	IF ZLIB_ADLER32
	and 1 << ZlibArchive_STATE_CHECKSUM_BIT
	ELSE
	xor a
	ENDIF
	ld (ix + ZlibArchive.state),a
	ld (ix + ZlibArchive.reader),l
	ld (ix + ZlibArchive.reader + 1),h
	push ix
	push de
	ld de,ZlibArchive.inflate
	add ix,de
	pop de
	call Inflate_Construct
	pop ix
	IF ZLIB_ADLER32
	push ix
	ld bc,ZlibArchive.adler32Checker
	add ix,bc
	call Adler32Checker_Construct
	pop ix
	ENDIF
	jp ZlibArchive_ReadHeader

; ix = this
; iy <- file reader
; Modifies: de
ZlibArchive_GetReaderIY:
	ld e,(ix + ZlibArchive.reader)
	ld d,(ix + ZlibArchive.reader + 1)
	ld iyl,e
	ld iyh,d
	ret

; ix = this
ZlibArchive_ReadHeader:
	call ZlibArchive_GetReaderIY
	call Reader_ReadWordBE_IY
	call ZlibArchive_CheckFCHECK
	jp nz,System_ThrowException  ; invalid FCHECK
	ld a,d
	and 00001111B
	cp ZlibArchive_DEFLATE_ID
	jp nz,System_ThrowException  ; not DEFLATE
	ld (ix + ZlibArchive.cm),a
	ld a,d
	and 11110000B
	rrca
	rrca
	rrca
	rrca
	cp ZlibArchive_MAX_WINDOW + 1
	jp nc,System_ThrowException  ; invalid window size
	ld (ix + ZlibArchive.cinfo),a
	ld a,e
	and 00100000B
	ld hl,ZlibArchive_presetDictionaryError
	jp nz,System_ThrowExceptionWithMessage
	ld a,e
	and 11000000B
	rlca
	rlca
	ld (ix + ZlibArchive.flevel),a
	ret

; d = CMF
; e = FLG
; f <- nz: invalid
; Modifies: af, bc, hl
ZlibArchive_CheckFCHECK: PROC
	ld l,e
	ld h,d
	ld c,31
	xor a
	ld b,16
Loop:
	add hl,hl
	rla
	cp c
	jr c,NoAdd
	sub c
	inc l
NoAdd:
	djnz Loop
	and a
	ret
	ENDP

; ix = this
ZlibArchive_ReadFooter:
	call ZlibArchive_GetReaderIY
	call Reader_ReadDoubleWordBE_IY
	IF ZLIB_ADLER32
	ld (ix + ZlibArchive.adler32),l
	ld (ix + ZlibArchive.adler32 + 1),h
	ld (ix + ZlibArchive.adler32 + 2),e
	ld (ix + ZlibArchive.adler32 + 3),d
	ENDIF
	ret

; ix = this
; a <- >0: more data, 0: final data
; f <- nz: more data, z: final data
; de <- buffer address
; hl <- byte count
ZlibArchive_Inflate: PROC
	push ix
	ld de,ZlibArchive.inflate
	add ix,de
	call Inflate_Inflate
	pop ix
	call ZlibArchive_Update
	ret nz
	bit ZlibArchive_STATE_FOOTER_BIT,(ix + ZlibArchive.state)
	call z,Footer
	and a
	ret
Footer:
	set ZlibArchive_STATE_FOOTER_BIT,(ix + ZlibArchive.state)
	ex af,af'
	exx
	call ZlibArchive_ReadFooter
	call ZlibArchive_Verify
	exx
	ex af,af'
	ret
	ENDP

; de = buffer address
; hl = byte count
; ix = this
ZlibArchive_Update:
	IF ZLIB_ADLER32
	push af
	bit ZlibArchive_STATE_CHECKSUM_BIT,(ix + ZlibArchive.state)
	call nz,ZlibArchive_UpdateAdler32
	pop af
	ENDIF
	ret

	IF ZLIB_ADLER32

; de = buffer address
; hl = byte count
; ix = this
ZlibArchive_UpdateAdler32:
	push de
	push hl
	push ix
	ld bc,ZlibArchive.adler32Checker
	add ix,bc
	call Adler32Checker_UpdateAdler32
	pop ix
	pop hl
	pop de
	ret

	ENDIF

; ix = this
ZlibArchive_Verify:
	IF ZLIB_ADLER32
	call ZlibArchive_VerifyAdler32
	ld hl,ZlibArchive_adler32MismatchError
	jp nz,System_ThrowExceptionWithMessage
	ENDIF
	ret

	IF ZLIB_ADLER32

; ix = this
; f <- nz: mismatch
ZlibArchive_VerifyAdler32:
	bit ZlibArchive_STATE_CHECKSUM_BIT,(ix + ZlibArchive.state)
	ret z
	ld l,(ix + ZlibArchive.adler32)
	ld h,(ix + ZlibArchive.adler32 + 1)
	ld c,(ix + ZlibArchive.adler32 + 2)
	ld b,(ix + ZlibArchive.adler32 + 3)
	push ix
	ld de,ZlibArchive.adler32Checker
	add ix,de
	ex de,hl
	call Adler32Checker_VerifyAdler32
	pop ix
	ret

	ENDIF

;
ZlibArchive_presetDictionaryError:
	db "Preset dictionary not supported.",13,10,0

	IF ZLIB_ADLER32

ZlibArchive_adler32MismatchError:
	db "Inflated Adler32 checksum mismatch.",13,10,0

	ENDIF
