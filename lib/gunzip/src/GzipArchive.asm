;
; Gzip archive
;
GzipArchive_STATE_CHECKSUM_BIT: equ 0
GzipArchive_STATE_FOOTER_BIT: equ 1
GzipArchive_SIGNATURE_1: equ 1FH
GzipArchive_SIGNATURE_2: equ 8BH
GzipArchive_DEFLATE_ID: equ 8
GzipArchive_FTEXT: equ 1 << 0
GzipArchive_FHCRC: equ 1 << 1
GzipArchive_FEXTRA: equ 1 << 2
GzipArchive_FNAME: equ 1 << 3
GzipArchive_FCOMMENT: equ 1 << 4
GzipArchive_RESERVED: equ 1 << 5 | 1 << 6 | 1 << 7

GzipArchive: MACRO
	state:
		db 0
	reader:
		dw 0
	count:
		dd 0
	flags:
		db 0
	mtime:
		dd 0
	xfl:
		db 0
	os:
		db 0
	isize:
		dd 0
	crc32:
		IF GZIP_CRC32
		dd 0
		ENDIF
	inflate:
		Inflate
	crc32Checker:
		IF GZIP_CRC32
		CRC32Checker
		ENDIF
	_size:
	ENDM

; a = -1: CRC32 check enabled, 0: disabled
; bc = decoders buffer
; de = write buffer (32K, 256-byte aligned)
; hl = reader
; ix = this
; ix <- this
GzipArchive_Construct:
	IF GZIP_CRC32
	and 1 << GzipArchive_STATE_CHECKSUM_BIT
	ELSE
	xor a
	ENDIF
	ld (ix + GzipArchive.state),a
	ld (ix + GzipArchive.reader),l
	ld (ix + GzipArchive.reader + 1),h
	xor a
	ld (ix + GzipArchive.count),a
	ld (ix + GzipArchive.count + 1),a
	ld (ix + GzipArchive.count + 2),a
	ld (ix + GzipArchive.count + 3),a
	push ix
	push de
	ld de,GzipArchive.inflate
	add ix,de
	pop de
	call Inflate_Construct
	pop ix
	IF GZIP_CRC32
	push ix
	ld bc,GzipArchive.crc32Checker
	add ix,bc
	call CRC32Checker_Construct
	pop ix
	ENDIF
	jp GzipArchive_ReadHeader

; ix = this
; iy <- file reader
; Modifies: de
GzipArchive_GetReaderIY:
	ld e,(ix + GzipArchive.reader)
	ld d,(ix + GzipArchive.reader + 1)
	ld iyl,e
	ld iyh,d
	ret

; ix = this
GzipArchive_ReadHeader: PROC
	call GzipArchive_GetReaderIY
	call Reader_Read_IY
	cp GzipArchive_SIGNATURE_1
	ld hl,GzipArchive_notGzipError
	jp nz,System_ThrowExceptionWithMessage
	call Reader_Read_IY
	cp GzipArchive_SIGNATURE_2
	ld hl,GzipArchive_notGzipError
	jp nz,System_ThrowExceptionWithMessage
	call Reader_Read_IY
	cp GzipArchive_DEFLATE_ID
	jp nz,System_ThrowException  ; not DEFLATE
	call Reader_Read_IY
	ld (ix + GzipArchive.flags),a
	call Reader_ReadDoubleWord_IY
	ld (ix + GzipArchive.mtime),l
	ld (ix + GzipArchive.mtime + 1),h
	ld (ix + GzipArchive.mtime + 2),e
	ld (ix + GzipArchive.mtime + 3),d
	call Reader_Read_IY
	ld (ix + GzipArchive.xfl),a
	call Reader_Read_IY
	ld (ix + GzipArchive.os),a
	ld a,(ix + GzipArchive.flags)
	and GzipArchive_RESERVED
	jp nz,System_ThrowException  ; unknown flag
	ld a,(ix + GzipArchive.flags)
	and GzipArchive_FEXTRA
	call nz,SkipExtra
	ld a,(ix + GzipArchive.flags)
	and GzipArchive_FNAME
	call nz,SkipASCIIZ
	ld a,(ix + GzipArchive.flags)
	and GzipArchive_FCOMMENT
	call nz,SkipASCIIZ
	ld a,(ix + GzipArchive.flags)
	and GzipArchive_FHCRC
	call nz,SkipHeaderCRC
	ret
SkipExtra:
	call Reader_ReadWord_IY
	ld c,e
	ld b,d
	jp Reader_Skip_IY
SkipASCIIZ:
	call Reader_Read_IY
	and a
	jp nz,SkipASCIIZ
	ret
SkipHeaderCRC:
	equ Reader_ReadWord_IY
	ENDP

; ix = this
GzipArchive_ReadFooter:
	call GzipArchive_GetReaderIY
	call Reader_ReadDoubleWord_IY
	IF GZIP_CRC32
	ld (ix + GzipArchive.crc32),l
	ld (ix + GzipArchive.crc32 + 1),h
	ld (ix + GzipArchive.crc32 + 2),e
	ld (ix + GzipArchive.crc32 + 3),d
	ENDIF
	call Reader_ReadDoubleWord_IY
	ld (ix + GzipArchive.isize),l
	ld (ix + GzipArchive.isize + 1),h
	ld (ix + GzipArchive.isize + 2),e
	ld (ix + GzipArchive.isize + 3),d
	ret

; ix = this
; a <- >0: more data, 0: final data
; f <- nz: more data, z: final data
; de <- buffer address
; hl <- byte count
GzipArchive_Inflate: PROC
	push ix
	ld de,GzipArchive.inflate
	add ix,de
	call Inflate_Inflate
	pop ix
	call GzipArchive_Update
	ret nz
	bit GzipArchive_STATE_FOOTER_BIT,(ix + GzipArchive.state)
	call z,Footer
	and a
	ret
Footer:
	set GzipArchive_STATE_FOOTER_BIT,(ix + GzipArchive.state)
	ex af,af'
	exx
	call GzipArchive_ReadFooter
	call GzipArchive_Verify
	exx
	ex af,af'
	ret
	ENDP

; de = buffer address
; hl = byte count
; ix = this
GzipArchive_Update:
	push af
	call GzipArchive_UpdateCount
	IF GZIP_CRC32
	bit GzipArchive_STATE_CHECKSUM_BIT,(ix + GzipArchive.state)
	call nz,GzipArchive_UpdateCRC32
	ENDIF
	pop af
	ret

; de = buffer address
; hl = byte count
; ix = this
GzipArchive_UpdateCount:
	push hl
	ld c,(ix + GzipArchive.count)
	ld b,(ix + GzipArchive.count + 1)
	add hl,bc
	ld (ix + GzipArchive.count),l
	ld (ix + GzipArchive.count + 1),h
	pop hl
	ret nc
	inc (ix + GzipArchive.count + 2)
	ret nz
	inc (ix + GzipArchive.count + 3)
	ret

	IF GZIP_CRC32

; hl = byte count
; de = buffer address
; ix = this
GzipArchive_UpdateCRC32:
	push de
	push hl
	push ix
	ld bc,GzipArchive.crc32Checker
	add ix,bc
	call CRC32Checker_UpdateCRC32
	pop ix
	pop hl
	pop de
	ret

	ENDIF

; ix = this
GzipArchive_Verify:
	call GzipArchive_VerifyISIZE
	ld hl,GzipArchive_isizeMismatchError
	jp nz,System_ThrowExceptionWithMessage
	IF GZIP_CRC32
	call GzipArchive_VerifyCRC32
	ld hl,GzipArchive_crc32MismatchError
	jp nz,System_ThrowExceptionWithMessage
	ENDIF
	ret

; ix = this
; f <- nz: mismatch
GzipArchive_VerifyISIZE:
	ld a,(ix + GzipArchive.count)
	cp (ix + GzipArchive.isize)
	ret nz
	ld a,(ix + GzipArchive.count + 1)
	cp (ix + GzipArchive.isize + 1)
	ret nz
	ld a,(ix + GzipArchive.count + 2)
	cp (ix + GzipArchive.isize + 2)
	ret nz
	ld a,(ix + GzipArchive.count + 3)
	cp (ix + GzipArchive.isize + 3)
	ret

	IF GZIP_CRC32

; ix = this
; f <- nz: mismatch
GzipArchive_VerifyCRC32:
	bit GzipArchive_STATE_CHECKSUM_BIT,(ix + GzipArchive.state)
	ret z
	ld l,(ix + GzipArchive.crc32)
	ld h,(ix + GzipArchive.crc32 + 1)
	ld c,(ix + GzipArchive.crc32 + 2)
	ld b,(ix + GzipArchive.crc32 + 3)
	push ix
	ld de,GzipArchive.crc32Checker
	add ix,de
	ex de,hl
	call CRC32Checker_VerifyCRC32
	pop ix
	ret

	ENDIF

;
GzipArchive_notGzipError:
	db "Not a GZIP file.",13,10,0

GzipArchive_isizeMismatchError:
	db "Inflated size mismatch.",13,10,0

	IF GZIP_CRC32

GzipArchive_crc32MismatchError:
	db "Inflated CRC32 mismatch.",13,10,0

	ENDIF
