;
; CRC32 checker unit tests
;
CRC32CheckerTest_Test:
	IF GZIP_CRC32
	call CRC32CheckerTest_TestCRC32
	ENDIF
	ret

	IF GZIP_CRC32

CRC32CheckerTest_TestCRC32: PROC
	ld ix,CRC32CheckerTest_crc32Checker
	call CRC32Checker_Construct

	ld de,0
	ld bc,0
	ld ix,CRC32CheckerTest_crc32Checker
	call CRC32Checker_VerifyCRC32
	call nz,System_ThrowException

	ld b,58
	ld hl,WRITEBUFFER
Loop1:
	ld (hl),b
	inc hl
	djnz Loop1
	ld hl,58
	ld de,WRITEBUFFER
	call CRC32Checker_UpdateCRC32
	ld de,07364H
	ld bc,0DAA8H
	ld ix,CRC32CheckerTest_crc32Checker
	call CRC32Checker_VerifyCRC32
	call nz,System_ThrowException

	ld b,200
	ld hl,WRITEBUFFER
Loop2:
	ld (hl),b
	inc hl
	djnz Loop2
	ld hl,200
	ld de,WRITEBUFFER
	call CRC32Checker_UpdateCRC32
	ld de,04E96H
	ld bc,02DA9H
	ld ix,CRC32CheckerTest_crc32Checker
	call CRC32Checker_VerifyCRC32
	call nz,System_ThrowException
	ret
	ENDP

;
CRC32CheckerTest_crc32Checker:
	CRC32Checker

	ENDIF
