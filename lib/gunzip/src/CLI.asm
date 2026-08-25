;
; Command-line interface parser
;
CLI_BUFFER_SIZE: equ 255

CLI: MACRO
	archivePath:
		dw 0
	outputPath:
		dw 0
	quiet:
		db 0
	fast:
		db 0
	buffer:
		ds CLI_BUFFER_SIZE
	_size:
	ENDM

; ix = this
; ix <- this
CLI_Construct:
	call CLI_GetBuffer
	ld hl,CLI_parametersEnvName
	ld b,255
	call DOS_GetEnvironmentItem
	ret

; ix = this
; de <- buffer
; Modifies: hl
CLI_GetBuffer:
	ld e,ixl
	ld d,ixh
	ld hl,CLI.buffer
	add hl,de
	ex de,hl
	ret

; ix = this
CLI_Parse: PROC
	call CLI_GetBuffer
Loop:
	ld a,(de)
	and a
	ret z
	cp "/"
	jr z,Option
	cp " "
	jr nz,Path
	inc de
	jp Loop
Option:
	call CLI_ParseOption
	jp Loop
Path:
	call CLI_ParsePath
	jp Loop
	ENDP

; de = buffer position
; ix = this
CLI_ParseOption: PROC
	inc de
	ld a,(de)
	and 11011111B  ; upper-case
	cp "Q"
	jr z,OptionQuiet
	cp "F"
	jr z,OptionFast
	ld hl,CLI_unknownOptionError
	jp System_ThrowExceptionWithMessage
OptionQuiet:
	ld (ix + CLI.quiet),-1
	inc de
	jp Next
OptionFast:
	ld (ix + CLI.fast),-1
	inc de
	jp Next
Next:
	ld a,(de)
	and a
	ret z
	cp " "
	ret z
	ld hl,CLI_unknownOptionError
	jp System_ThrowExceptionWithMessage
	ENDP

; de = buffer position
; ix = this
CLI_ParsePath: PROC
	ld a,(ix + CLI.archivePath)
	or (ix + CLI.archivePath + 1)
	jp nz,OutputPath
	ld (ix + CLI.archivePath),e
	ld (ix + CLI.archivePath + 1),d
Continue:
	ld b,0
	call DOS_ParsePathname
	ld a,(de)
	and a
	ret z
	ld a,0
	ld (de),a
	inc de
	ret
OutputPath:
	ld a,(ix + CLI.outputPath)
	or (ix + CLI.outputPath + 1)
	ld hl,CLI_multiplePathsError
	jp nz,System_ThrowExceptionWithMessage
	ld (ix + CLI.outputPath),e
	ld (ix + CLI.outputPath + 1),d
	jp Continue
	ENDP

;
CLI_parametersEnvName:
	db "PARAMETERS",0

CLI_unknownOptionError:
	db "Unknown command line option.",13,10,0

CLI_multiplePathsError:
	db "Can not specify additional file paths.",13,10,0
