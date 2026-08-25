;
; Streams a VGM file directly from disk, in a single sequential pass:
;  - PCM data blocks with a known chip-memory destination (OPL4/DalSoRi R2,
;    Neotron YM2610/B, Makoto/OPNA-on-SFG YM2608, MSX-AUDIO Y8950) are
;    streamed straight into that chip's own memory, in chunks, and are never
;    stored in system RAM.
;  - Everything else (register writes, waits, the end marker, and any data
;    block type that isn't diverted above, e.g. turboR PCM type 0) is
;    copied byte for byte into a compact command buffer in system RAM.
;
; Playback afterwards reads only from that compact buffer, so its timing is
; unaffected by disk access. The loop offset (if any) is translated from a
; position in the original file to the matching position in the compact
; buffer while scanning.
;
StreamLoader: MACRO
	reader:
		dw 0  ; pointer to a StreamFileReader instance, constructed and owned
		      ; externally (see StreamLoader_SetReader)
	writer:
		CommandWriter
	header:
		dw 0
	hasLoop:
		db 0
	loopFound:
		db 0
	trueDataOffset:
		dd 0
	sourcePosition:
		dd 0
	loopSourceOffset:
		dd 0
	loopBufferPosition:
		dd 0
	blockSize:
		dd 0
	payloadRemaining:
		dd 0
	blockHeader:
		ds 6  ; raw [0x66, type, size0, size1, size2, size3]
	_size:
	ENDM

; ix = this
; ix <- reader
; Modifies: de
StreamLoader_GetReader:
	ld e,(ix + StreamLoader.reader + 0)
	ld d,(ix + StreamLoader.reader + 1)
	ld ixl,e
	ld ixh,d
	ret

; ix = this
; iy <- reader
StreamLoader_GetReader_IY:
	ld e,(ix + StreamLoader.reader + 0)
	ld d,(ix + StreamLoader.reader + 1)
	ld iyl,e
	ld iyh,d
	ret

; de = reader pointer (a StreamFileReader instance, constructed and owned by
;      the caller)
; ix = this
StreamLoader_SetReader:
	ld (ix + StreamLoader.reader + 0),e
	ld (ix + StreamLoader.reader + 1),d
	ret

; ix = this
; ix <- writer
StreamLoader_GetWriter:
	ld de,StreamLoader.writer
	add ix,de
	ret

; ix = this
; ix <- header
StreamLoader_GetHeader:
	ld e,(ix + StreamLoader.header + 0)
	ld d,(ix + StreamLoader.header + 1)
	ld ixl,e
	ld ixh,d
	ret

; The StreamFileReader is constructed and destructed separately by the
; caller and wired in via StreamLoader_SetReader - see
; Application_OpenAndConstructStreamLoader.
;
; de = mapped buffer (backing the compact command buffer)
; ix = this
StreamLoader_Construct:
	; StreamLoader_GetWriter uses DE as its structure offset.  Preserve the
	; caller's mapped-buffer pointer, otherwise CommandWriter_Construct sees
	; DE=2 (the writer field offset) and subsequently grows address 0002H
	; instead of MappedBuffer_instance.
	push de
	push ix
	call StreamLoader_GetWriter
	pop hl
	pop de
	push hl
	call CommandWriter_Construct
	pop ix
	push ix
	ld bc,Header._size
	ld ix,Heap_main
	call Heap_Allocate
	pop ix
	ld (ix + StreamLoader.header + 0),e
	ld (ix + StreamLoader.header + 1),d
	ret

; ix = this
StreamLoader_Destruct: equ System_Return
;	ret

; bc = count
; hl = source
; ix = this
; ix <- this (preserved)
; Modifies: af, bc, de, hl
StreamLoader_AppendToWriter: PROC
	push ix
	call StreamLoader_GetWriter
	call CommandWriter_Append
	pop ix
	ret
	ENDP

; a = amount (0-255) to add to the running source-file position
; ix = this
StreamLoader_AdvanceSourcePositionByA: PROC
	ld e,a
	ld d,0
	ld l,(ix + StreamLoader.sourcePosition + 0)
	ld h,(ix + StreamLoader.sourcePosition + 1)
	add hl,de
	ld (ix + StreamLoader.sourcePosition + 0),l
	ld (ix + StreamLoader.sourcePosition + 1),h
	ret nc
	inc (ix + StreamLoader.sourcePosition + 2)
	ret nz
	inc (ix + StreamLoader.sourcePosition + 3)
	ret
	ENDP

; Adds StreamLoader.blockSize to StreamLoader.sourcePosition
; ix = this
StreamLoader_AdvanceSourcePositionByBlockSize: PROC
	ld a,(ix + StreamLoader.blockSize + 0)
	add a,(ix + StreamLoader.sourcePosition + 0)
	ld (ix + StreamLoader.sourcePosition + 0),a
	ld a,(ix + StreamLoader.blockSize + 1)
	adc a,(ix + StreamLoader.sourcePosition + 1)
	ld (ix + StreamLoader.sourcePosition + 1),a
	ld a,(ix + StreamLoader.blockSize + 2)
	adc a,(ix + StreamLoader.sourcePosition + 2)
	ld (ix + StreamLoader.sourcePosition + 2),a
	ld a,(ix + StreamLoader.blockSize + 3)
	adc a,(ix + StreamLoader.sourcePosition + 3)
	ld (ix + StreamLoader.sourcePosition + 3),a
	ret
	ENDP

; Reads the 256-byte header into StreamLoader.header and patches it for the
; compact command buffer.  It deliberately leaves the reader just after the
; header, which is required by the forward-only gzip path.
; ix = this
StreamLoader_ReadHeaderOnly: PROC
	push ix                        ; stack: [this]
	call StreamLoader_GetReader_IY  ; iy <- reader ; ix unchanged (= this)
	call StreamLoader_GetHeader      ; ix <- header
	call Header_Construct              ; reads 256 bytes via iy ; ix remains = header ; iy remains = reader

	call Header_GetDataOffset           ; ix = header ; dehl = TRUE original data offset
	ex (sp),ix                            ; ix <- this (stack top) ; stack top <- header
	ld (ix + StreamLoader.trueDataOffset + 0),l
	ld (ix + StreamLoader.trueDataOffset + 1),h
	ld (ix + StreamLoader.trueDataOffset + 2),e
	ld (ix + StreamLoader.trueDataOffset + 3),d
	ex (sp),ix                            ; ix <- header ; stack top <- this
	call StreamLoader_PatchDataOffsetField  ; ix = header (still)
	pop ix                                ; restore this
	ret
	ENDP


; Reads the header, then prints a plain-file GD3 tag by seeking directly to
; it.  This is intentionally separate from ReadHeaderOnly because a gzip
; reader cannot seek backwards after decompression has begun.
; ix = this
StreamLoader_ReadHeaderAndPrintTag: PROC
	call StreamLoader_ReadHeaderOnly
	push ix
	call StreamLoader_GetReader_IY
	call StreamLoader_GetHeader
	call Header_GetGD3Offset            ; ix = header ; f <- z: no GD3
	jr z,NoGD3
	call System_PrintCrLf
	call Header_GetGD3Offset            ; recompute dehl (ix, iy both still valid)
	call GD3_PrintInfoEnglishFromFile
NoGD3:
	call System_PrintCrLf
	pop ix                                ; restore this
	ret
	ENDP

; Starts scanning after a reader has already been positioned at the original
; VGM data offset.  Gzip streams cannot seek backwards, so their setup moves
; the reader forward once after parsing the header and then enters here.
; ix = this
StreamLoader_RunFromCurrentPosition: PROC
	call StreamLoader_SetInitialSourcePosition
	jp StreamLoader_RunCore
	ENDP

; a = opcode (already consumed from the reader)
; a <- operand byte count to also copy verbatim (0-11)
StreamLoader_GetOperandCount: PROC
	cp 30H
	jr c,Ret0        ; 00-2F -> 0
	cp 40H
	jr c,Ret1        ; 30-3F -> 1
	cp 4FH
	jr c,Ret2        ; 40-4E -> 2
	cp 51H
	jr c,Ret1        ; 4F,50 -> 1
	cp 60H
	jr c,Ret2        ; 51-5F -> 2
	cp 61H
	jr c,Unsupported ; 60
	cp 62H
	jr c,Ret2        ; 61 (wait nn nn) -> 2
	cp 64H
	jr c,Ret0        ; 62,63 -> 0
	cp 66H
	jr c,Unsupported ; 64,65
	cp 68H
	jr c,Ret0        ; 66,67 (handled by caller before reaching here)
	cp 69H
	jr c,Ret11       ; 68 -> 11
	cp 70H
	jr c,Unsupported ; 69-6F
	cp 90H
	jr c,Ret0        ; 70-8F -> 0
	cp 92H
	jr c,Ret4        ; 90,91 -> 4
	cp 93H
	jr c,Ret5        ; 92 -> 5
	cp 94H
	jr c,Ret10       ; 93 -> 10
	cp 95H
	jr c,Ret1        ; 94 -> 1
	cp 96H
	jr c,Ret4        ; 95 -> 4
	cp 0A0H
	jr c,Unsupported ; 96-9F
	cp 0C0H
	jr c,Ret2        ; A0-BF -> 2
	cp 0E0H
	jr c,Ret3        ; C0-DF -> 3
	jr Ret4          ; E0-FF -> 4
Ret0:
	xor a
	ret
Ret1:
	ld a,1
	ret
Ret2:
	ld a,2
	ret
Ret3:
	ld a,3
	ret
Ret4:
	ld a,4
	ret
Ret5:
	ld a,5
	ret
Ret10:
	ld a,10
	ret
Ret11:
	ld a,11
	ret
Unsupported:
	jp Player_UnsupportedCommand
	ENDP

; iy = reader
; ix = this
; a <- type
; b <- dual flag (bit7)
; dehl <- payload size (bit7 of msb cleared)
StreamLoader_ReadBlockHeaderRaw: PROC
	call Reader_Read_IY
	cp 66H
	jp nz,Player_UnsupportedCommand
	ld (ix + StreamLoader.blockHeader + 0),a
	call Reader_Read_IY
	ld (ix + StreamLoader.blockHeader + 1),a
	push af
	call Reader_Read_IY
	ld (ix + StreamLoader.blockHeader + 2),a
	ld l,a
	call Reader_Read_IY
	ld (ix + StreamLoader.blockHeader + 3),a
	ld h,a
	call Reader_Read_IY
	ld (ix + StreamLoader.blockHeader + 4),a
	ld e,a
	call Reader_Read_IY
	ld (ix + StreamLoader.blockHeader + 5),a
	ld d,a
	ld b,d
	res 7,d
	pop af
	ret
	ENDP

; dehl = payload size (d expected 0; blocks over 16 MB are not supported,
;        matching the existing OPL4/Neotron/Makoto loaders)
; ix = this
; iy = reader
StreamLoader_CopyPayloadVerbatim: PROC
	ld a,d
	and a
	call nz,System_ThrowException
	ld (ix + StreamLoader.payloadRemaining + 0),l
	ld (ix + StreamLoader.payloadRemaining + 1),h
	ld (ix + StreamLoader.payloadRemaining + 2),e
	ld (ix + StreamLoader.payloadRemaining + 3),0
Loop:
	ld a,(ix + StreamLoader.payloadRemaining + 0)
	or (ix + StreamLoader.payloadRemaining + 1)
	or (ix + StreamLoader.payloadRemaining + 2)
	ret z
	ld c,(ix + StreamLoader.payloadRemaining + 0)
	ld b,(ix + StreamLoader.payloadRemaining + 1)
	ld a,(ix + StreamLoader.payloadRemaining + 2)
	and a
	jr z,LessThan64K
	ld bc,0FFFFH
LessThan64K:
	call Reader_ReadBlockDirect_IY  ; bc <= requested, hl <- source
	push bc
	call StreamLoader_AppendToWriter
	pop bc
	ld l,(ix + StreamLoader.payloadRemaining + 0)
	ld h,(ix + StreamLoader.payloadRemaining + 1)
	and a
	sbc hl,bc
	ld (ix + StreamLoader.payloadRemaining + 0),l
	ld (ix + StreamLoader.payloadRemaining + 1),h
	jr nc,Loop
	dec (ix + StreamLoader.payloadRemaining + 2)
	jr Loop
	ENDP

; dehl = payload size (with dual-chip bit cleared)
; ix = this
; iy = reader
StreamLoader_CopyBlockVerbatim: PROC
	push de
	push hl
	ld hl,StreamLoader_literal67
	ld bc,1
	call StreamLoader_AppendToWriter
	push ix
	pop hl
	ld bc,StreamLoader.blockHeader
	add hl,bc
	ld bc,6
	call StreamLoader_AppendToWriter
	pop hl
	pop de
	jp StreamLoader_CopyPayloadVerbatim
	ENDP

StreamLoader_literal67:
	db 67H

StreamLoader_paddingByte:
	db 0

; a = type
; b = dual flag (bit7)
; dehl = payload size
; ix = this
; iy = reader
StreamLoader_DispatchDataBlock: PROC
	cp 81H
	jr z,YM2608
	cp 82H
	jr z,YM2610A
	cp 83H
	jr z,YM2610B
	cp 84H
	jr z,OPL4ROM
	cp 87H
	jr z,OPL4RAM
	cp 88H
	jr z,Y8950
	jp StreamLoader_CopyBlockVerbatim
YM2608:
	push de
	push hl
	push iy
	ld hl,StreamLoader_nameYM2608
	call Progress_StartBlock
	pop iy
	pop hl
	pop de
	push ix
	call YM2608_instance.ProcessDataBlock
	pop ix
	jp Progress_EndBlock
YM2610A:
	push de
	push hl
	push iy
	ld hl,StreamLoader_nameYM2610A
	call Progress_StartBlock
	pop iy
	pop hl
	pop de
	push ix
	call YM2610_instance.ProcessDataBlockA
	pop ix
	jp Progress_EndBlock
YM2610B:
	push de
	push hl
	push iy
	ld hl,StreamLoader_nameYM2610B
	call Progress_StartBlock
	pop iy
	pop hl
	pop de
	push ix
	call YM2610_instance.ProcessDataBlockB
	pop ix
	jp Progress_EndBlock
OPL4ROM:
	push de
	push hl
	push iy
	ld hl,StreamLoader_nameOPL4ROM
	call Progress_StartBlock
	pop iy
	pop hl
	pop de
	push ix
	call YMF278B_instance.ProcessROMDataBlock
	pop ix
	jp Progress_EndBlock
OPL4RAM:
	push de
	push hl
	push iy
	ld hl,StreamLoader_nameOPL4RAM
	call Progress_StartBlock
	pop iy
	pop hl
	pop de
	push ix
	call YMF278B_instance.ProcessRAMDataBlock
	pop ix
	jp Progress_EndBlock
Y8950:
	push de
	push hl
	push iy
	ld hl,StreamLoader_nameY8950
	call Progress_StartBlock
	pop iy
	pop hl
	pop de
	push ix
	call Y8950_instance.ProcessDataBlock
	pop ix
	jp Progress_EndBlock
	ENDP

StreamLoader_nameYM2608:
	db "YM2608 ADPCM",0
StreamLoader_nameYM2610A:
	db "YM2610 PCM-A",0
StreamLoader_nameYM2610B:
	db "YM2610 PCM-B",0
StreamLoader_nameOPL4ROM:
	db "OPL4 ROM",0
StreamLoader_nameOPL4RAM:
	db "OPL4 RAM",0
StreamLoader_nameY8950:
	db "Y8950 ADPCM",0

; bc = count
; ix = this
; iy = reader
; Modifies: af, bc, de, hl
StreamLoader_CopyFromReader: PROC
Loop:
	ld a,b
	or c
	ret z
	push bc
	call Reader_ReadBlockDirect_IY  ; bc <= requested, hl <- source
	push bc
	call StreamLoader_AppendToWriter
	pop bc
	pop hl
	and a
	sbc hl,bc
	ld c,l
	ld b,h
	jr Loop
	ENDP

; ix = this
StreamLoader_CheckLoopPoint: PROC
	ld a,(ix + StreamLoader.hasLoop)
	and a
	ret z
	ld a,(ix + StreamLoader.loopFound)
	and a
	ret nz
	ld a,(ix + StreamLoader.sourcePosition + 0)
	cp (ix + StreamLoader.loopSourceOffset + 0)
	ret nz
	ld a,(ix + StreamLoader.sourcePosition + 1)
	cp (ix + StreamLoader.loopSourceOffset + 1)
	ret nz
	ld a,(ix + StreamLoader.sourcePosition + 2)
	cp (ix + StreamLoader.loopSourceOffset + 2)
	ret nz
	ld a,(ix + StreamLoader.sourcePosition + 3)
	cp (ix + StreamLoader.loopSourceOffset + 3)
	ret nz
	push ix
	call StreamLoader_GetWriter
	call CommandWriter_GetSize
	pop ix
	ld (ix + StreamLoader.loopBufferPosition + 0),l
	ld (ix + StreamLoader.loopBufferPosition + 1),h
	ld (ix + StreamLoader.loopBufferPosition + 2),e
	ld (ix + StreamLoader.loopBufferPosition + 3),d
	ld (ix + StreamLoader.loopFound),0FFH
	ret
	ENDP

; ix = this
StreamLoader_PadBuffer: PROC
	; pad the compact buffer with 40H unused bytes, so that position 40H -
	; which Header_GetDataOffset now always resolves to, see
	; StreamLoader_PatchDataOffsetField - is where the real command data
	; begins. Player_ResetPosition is left completely unmodified.
	ld b,40H
Loop:
	push bc
	ld hl,StreamLoader_paddingByte
	ld bc,1
	call StreamLoader_AppendToWriter
	pop bc
	djnz Loop
	ret
	ENDP

; Sets StreamLoader.sourcePosition to StreamLoader.trueDataOffset.
; ix = this
; dehl <- trueDataOffset
StreamLoader_SetInitialSourcePosition: PROC
	ld l,(ix + StreamLoader.trueDataOffset + 0)
	ld h,(ix + StreamLoader.trueDataOffset + 1)
	ld e,(ix + StreamLoader.trueDataOffset + 2)
	ld d,(ix + StreamLoader.trueDataOffset + 3)
	ld (ix + StreamLoader.sourcePosition + 0),l
	ld (ix + StreamLoader.sourcePosition + 1),h
	ld (ix + StreamLoader.sourcePosition + 2),e
	ld (ix + StreamLoader.sourcePosition + 3),d
	ret
	ENDP

; Runs the plain-file (.vgm) scan: seeks the reader to trueDataOffset (cheap
; random access on a real file) before starting the shared scan core.
; ix = this
StreamLoader_Run: PROC
	call StreamLoader_PadBuffer
	call StreamLoader_SetInitialSourcePosition  ; dehl <- trueDataOffset
	push de
	push hl
	push ix
	call StreamLoader_GetReader_IY
	pop ix
	pop hl
	pop de
	call StreamFileReader_SetPosition_IY
	jp StreamLoader_RunCore
	ENDP

; ix = this
StreamLoader_RunCore: PROC
	push ix
	call StreamLoader_GetHeader
	call Header_GetLoopOffset
	pop ix
	jr z,NoLoop
	ld (ix + StreamLoader.hasLoop),0FFH
	ld (ix + StreamLoader.loopSourceOffset + 0),l
	ld (ix + StreamLoader.loopSourceOffset + 1),h
	ld (ix + StreamLoader.loopSourceOffset + 2),e
	ld (ix + StreamLoader.loopSourceOffset + 3),d
	jr Scan
NoLoop:
	ld (ix + StreamLoader.hasLoop),0
Scan:
	ld (ix + StreamLoader.loopFound),0

Loop:
	call StreamLoader_CheckLoopPoint

	push ix
	call StreamLoader_GetReader_IY
	call Reader_Read_IY
	pop ix
	cp 66H
	jr z,EndMarker
	cp 67H
	jr z,DataBlock

	push af
	call StreamLoader_GetOperandCount
	ld c,a
	pop af
	ld (ix + StreamLoader.blockHeader),a  ; reuse as 1-byte opcode scratch
	push bc
	ld hl,StreamLoader.blockHeader
	push ix
	pop de
	add hl,de
	ld bc,1
	call StreamLoader_AppendToWriter
	pop bc
	ld a,c
	inc a
	call StreamLoader_AdvanceSourcePositionByA
	ld a,c
	and a
	jr z,Loop
	ld b,0
	push ix
	call StreamLoader_GetReader_IY
	pop ix
	call StreamLoader_CopyFromReader
	jr Loop

DataBlock:
	push ix
	call StreamLoader_GetReader_IY
	pop ix
	call StreamLoader_ReadBlockHeaderRaw  ; a=type, b=dualflag, dehl=size
	push af
	push bc
	ld (ix + StreamLoader.blockSize + 0),l
	ld (ix + StreamLoader.blockSize + 1),h
	ld (ix + StreamLoader.blockSize + 2),e
	ld (ix + StreamLoader.blockSize + 3),d
	ld a,7
	call StreamLoader_AdvanceSourcePositionByA
	call StreamLoader_AdvanceSourcePositionByBlockSize
	pop bc
	pop af
	; reload dehl = size (clobbered by the position bookkeeping above)
	ld l,(ix + StreamLoader.blockSize + 0)
	ld h,(ix + StreamLoader.blockSize + 1)
	ld e,(ix + StreamLoader.blockSize + 2)
	ld d,(ix + StreamLoader.blockSize + 3)
	push ix
	push af
	push bc
	push de
	push hl
	call StreamLoader_GetReader_IY
	pop hl
	pop de
	pop bc
	pop af
	pop ix
	call StreamLoader_DispatchDataBlock
	jp Loop

EndMarker:
	call Progress_Finish
	ld a,1
	call StreamLoader_AdvanceSourcePositionByA
	ld hl,StreamLoader_endMarker
	ld bc,1
	call StreamLoader_AppendToWriter

	; finalise the loop offset translation
	ld a,(ix + StreamLoader.hasLoop)
	and a
	ret z
	ld a,(ix + StreamLoader.loopFound)
	and a
	jr nz,PatchLoop
	; loop point was never reached (shouldn't happen for a well-formed
	; file); fail safe by disabling the loop rather than risk an
	; out-of-range jump.
	push ix
	call StreamLoader_GetHeader
	xor a
	ld (ix + Header.loopOffset + 0),a
	ld (ix + Header.loopOffset + 1),a
	ld (ix + Header.loopOffset + 2),a
	ld (ix + Header.loopOffset + 3),a
	pop ix
	ret
PatchLoop:
	ld l,(ix + StreamLoader.loopBufferPosition + 0)
	ld h,(ix + StreamLoader.loopBufferPosition + 1)
	ld e,(ix + StreamLoader.loopBufferPosition + 2)
	ld d,(ix + StreamLoader.loopBufferPosition + 3)
	; StreamLoader_GetHeader uses DE for the header pointer.  Preserve the
	; complete 32-bit compact-buffer loop position while selecting the header,
	; otherwise the high word is replaced by that pointer on large tracks.
	push ix
	push de
	push hl
	call StreamLoader_GetHeader
	pop hl
	pop de
	call StreamLoader_PatchLoopOffsetField
	pop ix
	ret
	ENDP

; Overwrites the header's raw loopOffset field so that the existing
; Header_GetLoopOffset formula (raw + Header.loopOffset) yields the given
; absolute position within the compact command buffer.
; ix = header
; dehl = desired absolute position within the compact buffer
StreamLoader_PatchLoopOffsetField: PROC
	ld bc,Header.loopOffset
	and a
	sbc hl,bc
	ex de,hl
	ld bc,0
	sbc hl,bc
	ex de,hl
	ld (ix + Header.loopOffset + 0),l
	ld (ix + Header.loopOffset + 1),h
	ld (ix + Header.loopOffset + 2),e
	ld (ix + Header.loopOffset + 3),d
	ret
	ENDP

; Overwrites the header's raw vgmDataOffset field so that the existing
; Header_GetDataOffset formula yields 40H, regardless of VGM version or
; whatever value the file originally declared. The compact command buffer
; always places 40H bytes of (unused) padding before the real command data
; for exactly this reason, so Player_ResetPosition (which still calls
; Header_GetDataOffset, unmodified) lands in the right place without any
; changes to Player.asm.
; ix = header
StreamLoader_PatchDataOffsetField: PROC
	ld de,0
	ld hl,40H
	ld bc,Header.vgmDataOffset
	and a
	sbc hl,bc
	ex de,hl
	ld bc,0
	sbc hl,bc
	ex de,hl
	ld (ix + Header.vgmDataOffset + 0),l
	ld (ix + Header.vgmDataOffset + 1),h
	ld (ix + Header.vgmDataOffset + 2),e
	ld (ix + Header.vgmDataOffset + 3),d
	ret
	ENDP

StreamLoader_endMarker:
	db 66H
