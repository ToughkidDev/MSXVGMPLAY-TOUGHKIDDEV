;
; A Reader that streams bytes directly from a DOS file handle, without
; ever loading the whole file into memory. Used to scan a VGM file (and to
; divert PCM data blocks straight to sound chip memory) while keeping only
; a small read-ahead chunk resident in RAM.
;
; The read-ahead chunk reuses READBUFFER, which is otherwise unused while a
; plain (non-VGZ) VGM file is being streamed.
;
StreamFileReader_BUFFER: equ READBUFFER
StreamFileReader_BUFFER_SIZE: equ READBUFFER_SIZE

StreamFileReader: MACRO
	super: Reader
	fileHandle:
		db 0FFH
	_size:
	ENDM

; Reader contains a short self-modifying read trampoline.  Instances must
; therefore be copied from this initialized template, rather than obtained
; as raw heap memory.
StreamFileReader_class: Class StreamFileReader, StreamFileReader_template, Heap_main
StreamFileReader_template: StreamFileReader

; hl = file path (or a FileInfoBlock pointer - DOS_OpenFileHandle accepts
;      either via its "de" parameter)
; ix = this
; ix <- this
StreamFileReader_Construct:
	push ix
	ex de,hl        ; de = file path/FileInfoBlock, as DOS_OpenFileHandle needs
	ld a,00000001B  ; read-only
	call DOS_OpenFileHandle
	call DOS_TerminateIfError
	pop ix
	ld (ix + StreamFileReader.fileHandle),b
	ld de,StreamFileReader_Supply_IY
	jp Reader_Construct

; ix = this
StreamFileReader_Destruct:
	ld b,(ix + StreamFileReader.fileHandle)
	call DOS_CloseFileHandle
	jp DOS_TerminateIfError

; iy = this
; de <- buffer start
; hl <- buffer size (actual bytes read this refill)
; Modifies: af, bc
StreamFileReader_Supply_IY:
	ld de,StreamFileReader_BUFFER
	ld hl,StreamFileReader_BUFFER_SIZE
	ld b,(iy + StreamFileReader.fileHandle)
	; DOS calls do not promise to preserve either index register.  This reader
	; is called from StreamLoader with IX still pointing at the loader and IY
	; pointing at the reader, so retain both across the file operation.
	push ix
	push iy
	call DOS_ReadFromFileHandle
	pop iy
	pop ix
	call DOS_TerminateIfError
	ld a,h
	or l
	jp z,StreamFileReader_UnexpectedEndOfFile
	; Reader keeps its buffer end as a page number, so its supplied ranges
	; must end on a 256-byte boundary.  DOS may return a short final read
	; (notably when a GD3 tag ends at EOF).  Pad only that in-RAM tail; valid
	; VGM parsing stops before the padding and a later refill still reports
	; EOF normally.
	ld a,l
	and a
	jr z,StreamFileReader_SupplyAligned
	push hl
	neg                               ; A = bytes needed to reach next page
	ld c,a
	ld b,0
	ld de,StreamFileReader_BUFFER
	add hl,de                         ; HL = first padding byte
	xor a
StreamFileReader_PadLoop:
	ld (hl),a
	inc hl
	dec bc
	ld a,b
	or c
	jr nz,StreamFileReader_PadLoop
	pop hl                            ; restore actual byte count
	inc h
	ld l,0                            ; return rounded-up buffer length
StreamFileReader_SupplyAligned:
	ld de,StreamFileReader_BUFFER
	ret

; dehl = absolute file offset
; iy = this
; Modifies: af, bc, de, hl
StreamFileReader_SetPosition_IY:
	push ix                              ; retain caller's StreamLoader
	push iy
	pop ix                               ; ix = reader for the handle lookup
	ld b,(ix + StreamFileReader.fileHandle)
	push ix                              ; DOS may clobber IY
	call DOS_SetFileHandlePointer
	pop iy
	call DOS_TerminateIfError
	ld (iy + Reader.address + 0),0FFH
	ld (iy + Reader.address + 1),000H
	ld (iy + Reader.bufferEnd),000H
	pop ix                               ; restore caller's StreamLoader
	ret

StreamFileReader_UnexpectedEndOfFile:
	ld hl,StreamFileReader_unexpectedEOFError
	jp System_ThrowExceptionWithMessage

;
StreamFileReader_unexpectedEOFError:
	db "Unexpected end of file.",13,10,0
