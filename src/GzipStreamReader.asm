;
; A Reader that streams decompressed bytes straight out of a .vgz (gzip)
; file, without ever materialising the whole inflated file in system RAM -
; extending the same benefit StreamFileReader already gives plain .vgm
; files to the much more common compressed .vgz case.
;
; Gzip decompression (Inflate_Inflate) needs a full 32K sliding window to
; do its work, and this codebase's memory map has no 32K of spare RAM: the
; window has to be borrowed from page1 (StreamLoader/driver code) and page2
; (CommandWriter's active segment) - exactly the two pages StreamLoader and
; CommandWriter themselves need whenever they are not decompressing.
;
; The two roles never run at the same time, so this reader time-multiplexes
; the pages instead of relocating any existing code: every time a fresh
; decompressed chunk is needed, page1+page2 are temporarily remapped to two
; dedicated "scratch" segments (allocated once, for this reader's whole
; lifetime, so the sliding window's contents survive being swapped out),
; GzipArchive_Inflate is run, a small RELAY_SIZE-sized slice is copied out
; into a page0-resident relay buffer, and page1+page2 are immediately
; restored - page1 to the program's own static code, page2 to whatever
; segment CommandWriter currently has selected (CommandWriter only
; re-selects its own segment lazily, on crossing into a new one - see
; CommandWriter_Append - so this reader must explicitly put page2 back
; where CommandWriter left it, not just to "a" segment).
;
; The relay buffer is what the generic Reader/StreamLoader machinery
; actually reads from, so none of that code needs to know borrowing is
; happening at all.
;
GzipStreamReader_RELAY_SIZE: equ 100H  ; must stay a multiple of 100H - see
                                        ; Reader_SetBuffer_IY's alignment check
GzipStreamReader_INFLATE_WINDOW: equ 4000H  ; the borrowed page1+page2 32K
                                             ; window - just an address,
                                             ; whichever segments happen to
                                             ; be paged in there at the time

GzipStreamReader: MACRO
	super:
		Reader
	fileHandle:
		db 0FFH
	decoders:
		dw 0
	normalPage1Slot:
		db 0
	normalPage1Segment:
		db 0
	normalPage2Slot:
		db 0
	normalPage2Segment:
		db 0
	scratchPage1Slot:
		db 0
	scratchPage1Segment:
		db 0
	scratchPage2Slot:
		db 0
	scratchPage2Segment:
		db 0
	chunkPos:
		dw 0
	chunkRemaining:
		dw 0
	relayFill:
		dw 0
	primeNeeded:
		dw 0
	finished:
		db 0
	fileSupplier:
		FileSupplier
	bitReader:
		BitReader
	gzipArchive:
		GzipArchive
	_size:
	ENDM

; Reader, FileSupplier, BitReader and Inflate contain small inline routines
; whose opcodes are part of the object state.  A raw Heap_Allocate leaves
; those bytes uninitialised, so instances must be created from this template.
GzipStreamReader_class: Class GzipStreamReader, GzipStreamReader_template, Heap_main
GzipStreamReader_template: GzipStreamReader

; hl = file path
; ix = this
GzipStreamReader_Construct:
	push hl
	push ix
	ld ix,Heap_main
	ld bc,Decoders._size
	call Heap_Allocate
	pop ix
	ld (ix + GzipStreamReader.decoders + 0),e
	ld (ix + GzipStreamReader.decoders + 1),d
	pop de
	ld a,00000001B  ; read-only
	call DOS_OpenFileHandle
	call nz,System_ThrowException
	ld (ix + GzipStreamReader.fileHandle),b
	push ix
	call GzipStreamReader_GetFileSupplier
	ld de,READBUFFER
	ld hl,READBUFFER_SIZE
	call FileSupplier_Construct
	ex (sp),ix
	pop hl
	push ix
	call GzipStreamReader_GetBitReader
	ex de,hl
	call BitReader_Construct
	ex (sp),ix
	pop hl
	push ix
	ld c,(ix + GzipStreamReader.decoders + 0)
	ld b,(ix + GzipStreamReader.decoders + 1)
	call GzipStreamReader_GetGzipArchive
	ld de,GzipStreamReader_INFLATE_WINDOW
	ld a,GZIP_CRC32 ? -1 : 0
	call GzipArchive_Construct
	pop ix

	; Match the original MappedGzipLoader's first 16K window: transfer the
	; initial page-2 freebie to inflate page 1.  It is removed from the command
	; buffer factory before that buffer is padded, so the two roles never share
	; the same segment.
	ld a,(MappedBuffer_instance.freebie + MapperSegment.segment)
	ld (ix + GzipStreamReader.scratchPage1Segment),a
	ld a,(MappedBuffer_instance.freebie + MapperSegment.slot)
	ld (ix + GzipStreamReader.scratchPage1Slot),a
	xor a
	ld (MappedBuffer_instance.freebie + MapperSegment.segment),a
	ld (MappedBuffer_instance.freebie + MapperSegment.slot),a

	; The other 16K is allocated immediately, before CommandWriter claims its
	; own first segment.  On the reference machine this yields window 1/4,
	; exactly matching the original loader.
	call MappedBuffer_AllocateSegment
	ld (ix + GzipStreamReader.scratchPage2Segment),a
	ld (ix + GzipStreamReader.scratchPage2Slot),b

	xor a
	ld (ix + GzipStreamReader.chunkRemaining + 0),a
	ld (ix + GzipStreamReader.chunkRemaining + 1),a
	ld (ix + GzipStreamReader.finished),a

	ld de,GzipStreamReader_Supply_IY
	jp Reader_Construct

; ix = this
GzipStreamReader_Destruct: PROC
	; Do not call Mapper.Free here.  Several MSX-DOS mapper implementations
	; replace page 2 while releasing a segment, invalidating the command buffer
	; mapping during normal program shutdown.  These two process-private
	; segments are reclaimed by MSX-DOS when this COM process terminates.
	ld e,(ix + GzipStreamReader.decoders + 0)
	ld d,(ix + GzipStreamReader.decoders + 1)
	push ix
	ld ix,Heap_main
	ld bc,Decoders._size
	call Heap_Free
	pop ix
	ld b,(ix + GzipStreamReader.fileHandle)
	push ix
	call DOS_CloseFileHandle
	pop ix
	jp nz,System_ThrowException
	ret
	ENDP

; ix = this
; ix <- file supplier
; Modifies: de
GzipStreamReader_GetFileSupplier:
	ld de,GzipStreamReader.fileSupplier
	add ix,de
	ret

; ix = this
; ix <- bit reader
; Modifies: de
GzipStreamReader_GetBitReader:
	ld de,GzipStreamReader.bitReader
	add ix,de
	ret

; ix = this
; ix <- gzip archive
; Modifies: de
GzipStreamReader_GetGzipArchive:
	ld de,GzipStreamReader.gzipArchive
	add ix,de
	ret

; ix = this
GzipStreamReader_SavePages: PROC
	; The caller can itself be executing from either mapper page.  Capture both
	; mappings so a later restore returns to that exact execution context.
	push ix
	ld h,40H
	call Memory_GetSlot
	pop ix
	ld (ix + GzipStreamReader.normalPage1Slot),a
	push ix
	ld h,40H
	call Mapper_instance.GetPH
	pop ix
	ld (ix + GzipStreamReader.normalPage1Segment),a
	push ix
	ld h,80H
	call Memory_GetSlot
	pop ix
	ld (ix + GzipStreamReader.normalPage2Slot),a
	push ix
	ld h,80H
	call Mapper_instance.GetPH
	pop ix
	ld (ix + GzipStreamReader.normalPage2Segment),a
	ret
	ENDP

; ix = this
GzipStreamReader_BorrowPages: PROC
	call GzipStreamReader_SavePages
	ld h,40H
	ld a,(ix + GzipStreamReader.scratchPage1Slot)
	push ix
	push hl
	call Memory_SetSlot
	pop hl
	pop ix
	ld a,(ix + GzipStreamReader.scratchPage1Segment)
	push ix
	call Mapper_instance.PutPH
	pop ix
	ld h,80H
	ld a,(ix + GzipStreamReader.scratchPage2Slot)
	push ix
	push hl
	call Memory_SetSlot
	pop hl
	pop ix
	ld a,(ix + GzipStreamReader.scratchPage2Segment)
	push ix
	call Mapper_instance.PutPH
	pop ix
	ret
	ENDP

; ix = this
GzipStreamReader_RestorePages: PROC
	ld h,40H
	ld a,(ix + GzipStreamReader.normalPage1Slot)
	push ix
	push hl
	call Memory_SetSlot
	pop hl
	pop ix
	ld a,(ix + GzipStreamReader.normalPage1Segment)
	push ix
	call Mapper_instance.PutPH
	pop ix

	ld h,80H
	ld a,(ix + GzipStreamReader.normalPage2Slot)
	push ix
	push hl
	call Memory_SetSlot
	pop hl
	pop ix
	ld a,(ix + GzipStreamReader.normalPage2Segment)
	push ix
	call Mapper_instance.PutPH
	pop ix
	ret
	ENDP

; Borrows page1+page2, runs one GzipArchive_Inflate call and stores its
; result in chunkPos/chunkRemaining. Leaves the pages BORROWED - the caller
; is responsible for calling GzipStreamReader_RestorePages once it is done
; reading out of the chunk.
; ix = this
; Modifies: af, bc, de, hl
GzipStreamReader_BorrowAndInflate: PROC
	call GzipStreamReader_BorrowPages
	push ix
	ld hl,GzipStreamReader_InflateBorrowedPages
	call System_TryCall
	pop ix
	call System_HasException
	ret z  ; success deliberately leaves the inflate window mapped for copying
	call GzipStreamReader_RestorePages
	jp System_Rethrow
	ENDP

; Runs only while pages 1+2 are mapped to the persistent inflate window.
; Its caller installs an exception boundary so those pages are restored even
; if the gzip stream is malformed or the inflater detects an invariant error.
; ix = this
GzipStreamReader_InflateBorrowedPages: PROC
	push ix
	ld de,GzipStreamReader.gzipArchive
	add ix,de
	call GzipArchive_Inflate  ; f: nz=more,z=final ; de<-addr ; hl<-count
	pop ix
	jr nz,Store
	set 0,(ix + GzipStreamReader.finished)
Store:
	ld (ix + GzipStreamReader.chunkPos + 0),e
	ld (ix + GzipStreamReader.chunkPos + 1),d
	ld (ix + GzipStreamReader.chunkRemaining + 0),l
	ld (ix + GzipStreamReader.chunkRemaining + 1),h
	ret
	ENDP

; iy = this
; de <- relay buffer start
; hl <- byte count
; Modifies: af, bc
GzipStreamReader_Supply_IY: PROC
	push ix  ; Reader_SupplyBuffer_IY's caller can be Header/StreamLoader
	push iy
	pop ix
	push iy  ; GzipArchive_Inflate uses IY for its inner BitReader
	xor a
	ld (ix + GzipStreamReader.relayFill + 0),a
	ld (ix + GzipStreamReader.relayFill + 1),a

	; Reader_SetBuffer_IY accepts only 256-byte-aligned buffer lengths.  An
	; Inflate call may finish a deflate block with a short, non-final output
	; slice, so collect successive slices until this relay is full.  Padding a
	; non-final slice would insert bogus VGM commands between real bytes.
FillRelay:
	ld a,(ix + GzipStreamReader.chunkRemaining + 0)
	or (ix + GzipStreamReader.chunkRemaining + 1)
	jr nz,HaveLeftover

	bit 0,(ix + GzipStreamReader.finished)
	jr nz,Finished

	call GzipStreamReader_BorrowAndInflate
	ld a,(ix + GzipStreamReader.chunkRemaining + 0)
	or (ix + GzipStreamReader.chunkRemaining + 1)
	jr nz,CopyOut
	; The final inflate call can carry no data.  It is only valid after this
	; supply already collected some output for the relay.
	call GzipStreamReader_RestorePages
	jr Finished

HaveLeftover:
	call GzipStreamReader_BorrowPages  ; re-borrow to reach the pending bytes

CopyOut:
	; bc = min(RELAY_SIZE - relayFill, chunkRemaining)
	ld c,(ix + GzipStreamReader.chunkRemaining + 0)
	ld b,(ix + GzipStreamReader.chunkRemaining + 1)
	ld l,(ix + GzipStreamReader.relayFill + 0)
	ld h,(ix + GzipStreamReader.relayFill + 1)
	ld de,GzipStreamReader_RELAY_SIZE
	and a
	ex de,hl
	sbc hl,de
	sbc hl,bc
	jr nc,HaveCount
	add hl,bc
	ld b,h
	ld c,l
HaveCount:
	ld l,(ix + GzipStreamReader.chunkPos + 0)
	ld h,(ix + GzipStreamReader.chunkPos + 1)
	ld de,GzipStreamReader_RELAY_BUFFER
	ld a,(ix + GzipStreamReader.relayFill + 0)
	add a,e
	ld e,a
	push bc
	call System_FastLDIR
	pop bc

	ld l,(ix + GzipStreamReader.chunkPos + 0)
	ld h,(ix + GzipStreamReader.chunkPos + 1)
	add hl,bc
	ld (ix + GzipStreamReader.chunkPos + 0),l
	ld (ix + GzipStreamReader.chunkPos + 1),h
	ld l,(ix + GzipStreamReader.chunkRemaining + 0)
	ld h,(ix + GzipStreamReader.chunkRemaining + 1)
	and a
	sbc hl,bc
	ld (ix + GzipStreamReader.chunkRemaining + 0),l
	ld (ix + GzipStreamReader.chunkRemaining + 1),h
	ld l,(ix + GzipStreamReader.relayFill + 0)
	ld h,(ix + GzipStreamReader.relayFill + 1)
	add hl,bc
	ld (ix + GzipStreamReader.relayFill + 0),l
	ld (ix + GzipStreamReader.relayFill + 1),h

	call GzipStreamReader_RestorePages
	ld a,(ix + GzipStreamReader.relayFill + 1)
	cp GzipStreamReader_RELAY_SIZE >> 8
	jr z,ReturnFullRelay
	jp FillRelay

Finished:
	ld a,(ix + GzipStreamReader.relayFill + 0)
	or (ix + GzipStreamReader.relayFill + 1)
	jp z,GzipStreamReader_UnexpectedEndOfFile
	; Only the actual end of the gzip stream is safe to pad: the VGM end marker
	; has already appeared before these filler bytes can be read.
	ld l,(ix + GzipStreamReader.relayFill + 0)
	ld h,(ix + GzipStreamReader.relayFill + 1)
	ld de,GzipStreamReader_RELAY_BUFFER
	add hl,de
	ex de,hl
	ld hl,GzipStreamReader_RELAY_SIZE
	ld c,(ix + GzipStreamReader.relayFill + 0)
	ld b,(ix + GzipStreamReader.relayFill + 1)
	or a
	sbc hl,bc
	xor a
PadFinalRelay:
	ld (de),a
	inc de
	dec hl
	ld a,h
	or l
	jr nz,PadFinalRelay

ReturnFullRelay:
	ld hl,GzipStreamReader_RELAY_SIZE
	ld de,GzipStreamReader_RELAY_BUFFER
	pop iy
	pop ix
	ret
	ENDP

; Primes the outer reader with a ready-made, exactly 256-byte buffer that
; starts precisely at the true VGM data offset, for the case where that
; offset falls within the 256 bytes Header_Construct already consumed (a
; gzip stream can only move forward, so those bytes can't be re-read live;
; they are replayed from the still-resident header snapshot instead, and
; the remainder of the 256-byte buffer is topped up with fresh, live
; decompressed bytes so the result is a normal, aligned buffer as far as
; the rest of the Reader machinery is concerned).
; de = header struct address
; hl = true VGM data offset (0-255; caller must ensure this - i.e. only
;      call this when the offset falls within the first 256 bytes)
; ix = this
GzipStreamReader_PrimeAfterHeader: PROC
	ld a,l
	cpl
	inc a
	ld c,a
	ld b,0
	ld a,c
	or a
	jr nz,GotReplayLen
	ld b,1  ; trueDataOffset was 0: replayLen = 256
GotReplayLen:
	; bc = replayLen (1-256)
	push bc
	add hl,de                  ; hl = header address + trueDataOffset (source)
	ld de,GzipStreamReader_RELAY_BUFFER
	call System_FastLDIR          ; copies bc(replayLen) header bytes
	pop bc                            ; bc = replayLen (restored)

	ld hl,100H
	and a
	sbc hl,bc
	ld (ix + GzipStreamReader.primeNeeded + 0),l
	ld (ix + GzipStreamReader.primeNeeded + 1),h
	ld a,h
	or l
	jp z,Primed  ; needed=0 only when trueDataOffset was 0

FillLoop:
	ld a,(ix + GzipStreamReader.chunkRemaining + 0)
	or (ix + GzipStreamReader.chunkRemaining + 1)
	jr nz,HaveChunk
	call GzipStreamReader_BorrowAndInflate
	jr CheckAvailable
HaveChunk:
	call GzipStreamReader_BorrowPages
CheckAvailable:
	ld l,(ix + GzipStreamReader.chunkRemaining + 0)
	ld h,(ix + GzipStreamReader.chunkRemaining + 1)
	ld a,h
	or l
	jr nz,HaveChunkAvailable
	call GzipStreamReader_RestorePages
	jp GzipStreamReader_UnexpectedEndOfFile
HaveChunkAvailable:
	; take = min(chunkRemaining, primeNeeded)
	ld c,(ix + GzipStreamReader.primeNeeded + 0)
	ld b,(ix + GzipStreamReader.primeNeeded + 1)
	and a
	sbc hl,bc
	jr nc,TakeIsNeeded
	add hl,bc
	ld b,h
	ld c,l
TakeIsNeeded:
	; bc = take ; dest = RELAY_BUFFER + (256 - primeNeeded)
	push bc
	ld hl,GzipStreamReader_RELAY_BUFFER + 100H
	ld e,(ix + GzipStreamReader.primeNeeded + 0)
	ld d,(ix + GzipStreamReader.primeNeeded + 1)
	and a
	sbc hl,de
	ex de,hl                     ; de = dest
	ld l,(ix + GzipStreamReader.chunkPos + 0)
	ld h,(ix + GzipStreamReader.chunkPos + 1)
	pop bc
	push bc
	call System_FastLDIR
	pop bc

	ld l,(ix + GzipStreamReader.chunkPos + 0)
	ld h,(ix + GzipStreamReader.chunkPos + 1)
	add hl,bc
	ld (ix + GzipStreamReader.chunkPos + 0),l
	ld (ix + GzipStreamReader.chunkPos + 1),h
	ld l,(ix + GzipStreamReader.chunkRemaining + 0)
	ld h,(ix + GzipStreamReader.chunkRemaining + 1)
	and a
	sbc hl,bc
	ld (ix + GzipStreamReader.chunkRemaining + 0),l
	ld (ix + GzipStreamReader.chunkRemaining + 1),h
	ld l,(ix + GzipStreamReader.primeNeeded + 0)
	ld h,(ix + GzipStreamReader.primeNeeded + 1)
	and a
	sbc hl,bc
	ld (ix + GzipStreamReader.primeNeeded + 0),l
	ld (ix + GzipStreamReader.primeNeeded + 1),h

	call GzipStreamReader_RestorePages

	; Mapper restore helpers modify HL.  Reload the persisted remaining count
	; before deciding whether another borrowed inflate slice is required.
	ld l,(ix + GzipStreamReader.primeNeeded + 0)
	ld h,(ix + GzipStreamReader.primeNeeded + 1)
	ld a,h
	or l
	jr nz,FillLoop

Primed:
	push ix
	pop iy
	ld de,GzipStreamReader_RELAY_BUFFER
	ld hl,100H
	jp Reader_SetBuffer_IY
	ENDP

GzipStreamReader_UnexpectedEndOfFile:
	ld hl,GzipStreamReader_unexpectedEOFError
	jp System_ThrowExceptionWithMessage

; Reads a gzip VGM header, positions its forward-only reader at the true VGM
; data offset, then patches/finalises the header for the compact buffer.  A
; number of valid VGM 1.50+ files start at 80H, inside the 256 bytes already
; consumed to parse the header; PrimeAfterHeader replays that untouched part
; before Header_Finalize clears it.
; ix = StreamLoader
StreamLoader_ReadGzipHeaderAndPosition: PROC
	push ix
	call StreamLoader_GetReader_IY
	call StreamLoader_GetHeader
	call Header_Read
	call Header_GetDataOffset
	ex (sp),ix
	ld (ix + StreamLoader.trueDataOffset + 0),l
	ld (ix + StreamLoader.trueDataOffset + 1),h
	ld (ix + StreamLoader.trueDataOffset + 2),e
	ld (ix + StreamLoader.trueDataOffset + 3),d
	ex (sp),ix
	ld a,d
	or e
	or h
	jr nz,AfterHeader
	push ix
	push ix
	pop de
	push iy
	pop ix
	call GzipStreamReader_PrimeAfterHeader
	pop ix
	call Header_Finalize
	call StreamLoader_PatchDataOffsetField
	pop ix
	ret
AfterHeader:
	call Header_Finalize
	call StreamLoader_PatchDataOffsetField
	pop ix
	ld l,(ix + StreamLoader.trueDataOffset + 0)
	ld h,(ix + StreamLoader.trueDataOffset + 1)
	ld e,(ix + StreamLoader.trueDataOffset + 2)
	ld d,(ix + StreamLoader.trueDataOffset + 3)
	ld bc,100H
	and a
	sbc hl,bc
	ex de,hl
	ld bc,0
	sbc hl,bc
	ex de,hl
	push de
	ld b,h
	ld c,l
	pop de
	jp Reader_Skip32_IY
	ENDP

;
GzipStreamReader_unexpectedEOFError:
	db "Unexpected end of file.",13,10,0

	SECTION RAM_PAGE0_ALIGNED

	ALIGN 100H
GzipStreamReader_RELAY_BUFFER: ds GzipStreamReader_RELAY_SIZE

	ENDS

; The inflater's state includes self-modifying Reader/BitReader/Inflate
; routines.  It must therefore remain visible while mapper pages 1 and 2
; are borrowed as the 32K inflate window.  Keep the sole process-wide reader
; in fixed page 0 rather than allocating it from Heap_main (which lives in
; mapper page 2 and disappears while the window is mapped).
	SECTION RAM_PAGE0


	ENDS
