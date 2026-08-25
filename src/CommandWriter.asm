;
; Growable buffer that VGM register/wait commands are sequentially appended
; into, while PCM data blocks are diverted straight to sound chip memory and
; never stored here. Backed by a MappedBuffer, reusing the same 16K load
; window previously used by MappedFileLoader (only one of the two is ever
; in use at a time).
;
CommandWriter_BUFFER_START: equ 8000H
CommandWriter_BUFFER_END: equ CommandWriter_BUFFER_START + 4000H

CommandWriter: MACRO
	buffer:
		dw 0
	position:
		dw CommandWriter_BUFFER_END  ; forces allocation of the first segment
	remaining:
		dw 0
	chunk:
		dw 0
	source:
		dw 0
	_size:
	ENDM

; de = mapped buffer
; ix = this
CommandWriter_Construct:
	ld (ix + CommandWriter.buffer + 0),e
	ld (ix + CommandWriter.buffer + 1),d
	ld (ix + CommandWriter.position + 0),CommandWriter_BUFFER_END & 0FFH
	ld (ix + CommandWriter.position + 1),CommandWriter_BUFFER_END >> 8
	ret

; ix = this
; dehl <- total size written so far
CommandWriter_GetSize: PROC
	ld e,(ix + CommandWriter.buffer + 0)
	ld d,(ix + CommandWriter.buffer + 1)
	push ix
	ld ixl,e
	ld ixh,d
	ld l,(ix + MappedBuffer.size + 0)
	ld h,(ix + MappedBuffer.size + 1)
	ld e,(ix + MappedBuffer.size + 2)
	ld d,(ix + MappedBuffer.size + 3)
	pop ix
	ret
	ENDP

; bc = byte count
; hl = source address
; ix = this
; Modifies: af, bc, de, hl
CommandWriter_Append: PROC
	ld (ix + CommandWriter.remaining + 0),c
	ld (ix + CommandWriter.remaining + 1),b
	ld (ix + CommandWriter.source + 0),l
	ld (ix + CommandWriter.source + 1),h
Loop:
	ld a,(ix + CommandWriter.remaining + 0)
	or (ix + CommandWriter.remaining + 1)
	ret z

	ld e,(ix + CommandWriter.position + 0)
	ld d,(ix + CommandWriter.position + 1)
	ld a,d
	cp CommandWriter_BUFFER_END >> 8
	call nc,NextSegment  ; de <- CommandWriter_BUFFER_START

	; hl = window space remaining = BUFFER_END - de
	ld hl,CommandWriter_BUFFER_END
	and a
	sbc hl,de
	ld c,(ix + CommandWriter.remaining + 0)
	ld b,(ix + CommandWriter.remaining + 1)
	and a
	sbc hl,bc  ; hl = windowSpace - remaining
	jr nc,ChunkIsRemaining  ; windowSpace >= remaining: copy it all this iteration
	add hl,bc  ; hl = windowSpace (undo the subtraction)
	ld b,h
	ld c,l  ; chunk = windowSpace
ChunkIsRemaining:
	ld (ix + CommandWriter.chunk + 0),c
	ld (ix + CommandWriter.chunk + 1),b
	ld l,(ix + CommandWriter.source + 0)
	ld h,(ix + CommandWriter.source + 1)
	call System_FastLDIR  ; hl <- source+chunk, de <- dest+chunk, bc <- 0
	ld (ix + CommandWriter.position + 0),e
	ld (ix + CommandWriter.position + 1),d
	ld (ix + CommandWriter.source + 0),l
	ld (ix + CommandWriter.source + 1),h

	; remaining -= chunk
	ld l,(ix + CommandWriter.remaining + 0)
	ld h,(ix + CommandWriter.remaining + 1)
	ld c,(ix + CommandWriter.chunk + 0)
	ld b,(ix + CommandWriter.chunk + 1)
	and a
	sbc hl,bc
	ld (ix + CommandWriter.remaining + 0),l
	ld (ix + CommandWriter.remaining + 1),h

	; grow the mapped buffer's logical size by chunk
	ld l,(ix + CommandWriter.chunk + 0)
	ld h,(ix + CommandWriter.chunk + 1)
	ld e,(ix + CommandWriter.buffer + 0)
	ld d,(ix + CommandWriter.buffer + 1)
	push ix
	ld ixl,e
	ld ixh,d
	call MappedBuffer_IncreaseSize
	pop ix
	jr Loop

; de <- CommandWriter_BUFFER_START
; ix = this
NextSegment:
	ld e,(ix + CommandWriter.buffer + 0)
	ld d,(ix + CommandWriter.buffer + 1)
	push ix
	ld ixl,e
	ld ixh,d
	call MappedBuffer_AllocateAndAddSegment
	ld h,CommandWriter_BUFFER_START >> 8
	call MappedBuffer_SelectSegment
	pop ix
	ld (ix + CommandWriter.position + 0),CommandWriter_BUFFER_START & 0FFH
	ld (ix + CommandWriter.position + 1),CommandWriter_BUFFER_START >> 8
	ld de,CommandWriter_BUFFER_START
	ret
	ENDP
