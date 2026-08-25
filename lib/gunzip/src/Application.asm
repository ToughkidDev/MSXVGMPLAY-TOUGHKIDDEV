;
; Top-level application program class
;
Application: MACRO
	archiveFileHandle:
		db 0FFH
	outputFileHandle:
		db 0FFH
	outputSize:
		dd 0
	archiveFIB:
		FileInfoBlock
	outputFIB:
		FileInfoBlock
	cli:
		CLI
	fileSupplier:
		FileSupplier
	bitReader:
		BitReader
	gzipArchive:
		GzipArchive
	_size:
	ENDM

;
Application_Main:
	call Application_CheckStack

	call CRC32CheckerTest_Test
	call AlphabetTest_Test

	ld ix,Application_instance
	call Application_Construct
	push ix
	ld hl,Application_EnterMainLoop
	call System_TryCall
	pop ix
	call Application_Destruct
	call System_Rethrow
	ret

; ix = this
; ix <- this
Application_Construct:
	push ix
	call Application_GetCLI
	call CLI_Construct
	pop ix
	ret

; ix = this
; ix <- this
Application_Destruct:
	ret

; ix = this
; ix <- command-line interface
; Modifies: f
Application_GetCLI:
	push de
	ld de,Application.cli
	add ix,de
	pop de
	ret

; ix = this
; ix <- file supplier
; Modifies: f
Application_GetFileSupplier:
	push de
	ld de,Application.fileSupplier
	add ix,de
	pop de
	ret

; ix = this
; ix <- bit reader
; Modifies: f
Application_GetBitReader:
	push de
	ld de,Application.bitReader
	add ix,de
	pop de
	ret

; ix = this
; ix <- gzip archive
; Modifies: f
Application_GetGzipArchive:
	push de
	ld de,Application.gzipArchive
	add ix,de
	pop de
	ret

; ix = this
Application_EnterMainLoop:
	call Application_ParseCLI
	call Application_PrintWelcome
	call Application_Inflate
	ret

; ix = this
Application_ParseCLI:
	push ix
	call Application_GetCLI
	call CLI_Parse
	ld l,(ix + CLI.archivePath)
	ld h,(ix + CLI.archivePath + 1)
	ld a,l
	or h
	ld hl,Application_usageInstructions
	jp z,System_ThrowExceptionWithMessage
	pop ix
	ret

; ix = this
Application_Inflate:
	call Application_IsTesting
	jp z,Application_InflateTest
	jp Application_InflateToFile

; ix = this
Application_InflateToFile: PROC
	call Application_FindNextFile
	ret c
	call Application_PrintInflating
	call Application_CreateFileReader
	push de
	call Application_ReadOutputSize
	call Application_IsFast
	cpl
	pop hl
	push ix
	call Application_GetGzipArchive
	ld bc,Application_decoders
	ld de,WRITEBUFFER
	call GzipArchive_Construct
	pop ix
	call Application_FindNewOutput
	call Application_CreateFileWriter
	call Application_PreAllocateOutput
InflateLoop:
	push ix
	call Application_GetGzipArchive
	call GzipArchive_Inflate
	pop ix
	push af
	push hl
	call DOS_ConsoleStatus  ; allow ctrl-c
	pop hl
	ld b,(ix + Application.outputFileHandle)
	call DOS_WriteToFileHandle
	call DOS_TerminateIfError
	call DOS_ConsoleStatus  ; allow ctrl-c
	pop af
	jr nz,InflateLoop
	ld b,(ix + Application.archiveFileHandle)
	call DOS_CloseFileHandle
	call DOS_TerminateIfError
	ld b,(ix + Application.outputFileHandle)
	call DOS_CloseFileHandle
	call DOS_TerminateIfError
	jr Application_InflateToFile
	ENDP

; ix = this
Application_InflateTest: PROC
	call Application_FindNextFile
	ret c
	call Application_PrintTesting
	call Application_CreateFileReader
	push de
	call Application_IsFast
	cpl
	pop hl
	push ix
	call Application_GetGzipArchive
	ld bc,Application_decoders
	ld de,WRITEBUFFER
	call GzipArchive_Construct
InflateLoop:
	call GzipArchive_Inflate
	jr nz,InflateLoop
	pop ix
	ld b,(ix + Application.archiveFileHandle)
	call DOS_CloseFileHandle
	call DOS_TerminateIfError
	jr Application_InflateTest
	ENDP

; ix = this
Application_PrintWelcome:
	call Application_IsQuiet
	ret nz
	ld hl,Application_welcome
	jp System_Print

; ix = this
Application_PrintInflating:
	call Application_IsQuiet
	ret nz
	ld hl,Application_inflatingFile
	call System_Print
	ld e,ixl
	ld d,ixh
	ld hl,Application.archiveFIB.name
	add hl,de
	call System_Print
	ld hl,Application_dotDotDot
	jp System_Print

; ix = this
Application_PrintTesting:
	call Application_IsQuiet
	ret nz
	ld hl,Application_testingFile
	call System_Print
	ld e,ixl
	ld d,ixh
	ld hl,Application.archiveFIB.name
	add hl,de
	call System_Print
	ld hl,Application_dotDotDot
	jp System_Print

; ix = this
; f <- nz: quiet
; Modifies: none
Application_IsQuiet:
	push ix
	call Application_GetCLI
	bit 0,(ix + CLI.quiet)
	pop ix
	ret

; ix = this
; a <- -1: fast
; Modifies: f
Application_IsFast:
	push ix
	call Application_GetCLI
	ld a,(ix + CLI.fast)
	pop ix
	ret

; ix = this
; f <- z: testing
; Modifies: a
Application_IsTesting:
	push ix
	call Application_GetCLI
	ld a,(ix + CLI.outputPath)
	or (ix + CLI.outputPath + 1)
	pop ix
	ret

; ix = this
; f <- c: done
Application_FindNextFile: PROC
	ld a,(ix + Application.archiveFIB + 1)
	and a
	jr nz,Next
First:
	push ix
	call Application_GetCLI
	ld e,(ix + CLI.archivePath)
	ld d,(ix + CLI.archivePath + 1)
	pop ix
	push ix
	ld bc,Application.archiveFIB
	add ix,bc
	call DOS_FindFirstEntry
	pop ix
	call DOS_TerminateIfError
	and a
	ret
Next:
	push ix
	ld bc,Application.archiveFIB
	add ix,bc
	call DOS_FindNextEntry
	pop ix
	cp .NOFIL
	scf
	ret z
	call DOS_TerminateIfError
	and a
	ret
	ENDP

; ix = this
Application_FindNewOutput:
	ld c,ixl
	ld b,ixh
	ld hl,Application.outputFIB.name
	add hl,bc
	ex de,hl
	ld hl,Application.archiveFIB.name
	add hl,bc
	ld bc,FileInfoBlock.attributes - FileInfoBlock.name
	ldir
	push ix
	call Application_GetCLI
	ld e,(ix + CLI.outputPath)
	ld d,(ix + CLI.outputPath + 1)
	pop ix
	push ix
	ld bc,Application.outputFIB
	add ix,bc
	ld b,0
	call DOS_FindNewEntry
	pop ix
	call DOS_TerminateIfError
	ret

; ix = this
; de <- file reader
Application_CreateFileReader:
	ld e,ixl
	ld d,ixh
	ld hl,Application.archiveFIB
	add hl,de
	ex de,hl
	ld a,00000001B  ; read only
	call DOS_OpenFileHandle
	call DOS_TerminateIfError
	ld (ix + Application.archiveFileHandle),b
	ld de,READBUFFER
	ld hl,READBUFFER_SIZE
	push ix
	call Application_GetFileSupplier
	call FileSupplier_Construct
	ld e,ixl
	ld d,ixh
	pop ix
	push ix
	call Application_GetBitReader
	call BitReader_Construct
	ld e,ixl
	ld d,ixh
	pop ix
	ret

; ix = this
; de <- file writer
Application_CreateFileWriter:
	ld e,ixl
	ld d,ixh
	ld hl,Application.outputFIB
	add hl,de
	ex de,hl
	ld a,00000010B  ; write only
	ld b,0
	call DOS_OpenFileHandle
	call DOS_TerminateIfError
	ld (ix + Application.outputFileHandle),b
	ret

; ix = this
; Modifies: af, bc, de, hl
Application_ReadOutputSize:
	ld b,(ix + Application.archiveFileHandle)
	call DOS_GetFileHandlePointer
	call DOS_TerminateIfError
	push de
	push hl
	ld a,2
	ld hl,-4 & 0FFFFH
	ld de,-4 >> 16
	ld b,(ix + Application.archiveFileHandle)
	call DOS_MoveFileHandlePointer
	call DOS_TerminateIfError
	ld e,ixl
	ld d,ixh
	ld hl,Application.outputSize
	add hl,de
	ex de,hl
	ld hl,4
	ld b,(ix + Application.archiveFileHandle)
	call DOS_ReadFromFileHandle
	call DOS_TerminateIfError
	pop hl
	pop de
	ld b,(ix + Application.archiveFileHandle)
	call DOS_SetFileHandlePointer
	jp DOS_TerminateIfError

; ix = this
; Modifies: af, bc, de, hl
Application_PreAllocateOutput:
	ld a,(ix + Application.outputSize + 2)
	or (ix + Application.outputSize + 3)
	ret z  ; don’t pre-allocate if < 64K
	ld b,(ix + Application.outputFileHandle)
	call DOS_GetFileHandlePointer
	call DOS_TerminateIfError
	push de
	push hl
	ld l,(ix + Application.outputSize)
	ld h,(ix + Application.outputSize + 1)
	ld e,(ix + Application.outputSize + 2)
	ld d,(ix + Application.outputSize + 3)
	ld bc,1
	sbc hl,bc
	dec bc
	ex de,hl
	sbc hl,bc
	ex de,hl
	ld b,(ix + Application.outputFileHandle)
	call DOS_SetFileHandlePointer
	call DOS_TerminateIfError
	ld de,0  ; don’t care which value we write
	ld hl,1
	ld b,(ix + Application.outputFileHandle)
	call DOS_WriteToFileHandle
	call DOS_TerminateIfError
	pop hl
	pop de
	ld b,(ix + Application.outputFileHandle)
	call DOS_SetFileHandlePointer
	call DOS_TerminateIfError
	ret

; Check if the stack is well above the heap
Application_CheckStack:
	ld hl,-(TPA_TOP + STACK_SIZE)
	add hl,sp
	ld hl,Application_insufficientTPAError
	jp nc,System_ThrowExceptionWithMessage
	ret

;
Application_instance:
	Application

Application_welcome:
	db "Gunzip 1.1 by Grauw",13,10,10,0

Application_inflatingFile:
	db "Inflating ",0

Application_testingFile:
	db "Testing ",0

Application_dotDotDot:
	db "...",13,10,0

Application_insufficientTPAError:
	db "Insufficient TPA space.",13,10,0

Application_usageInstructions:
	db "Usage: gunzip [options] <archive.gz> [<outputfi.le>]",13,10
	db 13,10
	db "Options:",13,10
	db "  /q  Quiet, suppress messages.",13,10
	db "  /f  Fast, no checksum validation.",13,10
	db 13,10
	db "Archive and output file names support wildcards."
	db "If no output file is specified, the archive will be tested.",13,10,0

	SECTION DECODERBUFFER

Application_decoders:
	Decoders

	ENDS
