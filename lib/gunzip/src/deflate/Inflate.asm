;
; Inflate implementation
;
Inflate_STATE_FINAL_BIT: equ 0
Inflate_STATE_COPY_BIT: equ 1
Inflate_STATE_COMPRESSED_BIT: equ 2
Inflate_BUFFER_SIZE: equ 8000H

Inflate: MACRO
	; a = value
	; hl = literal/length decoder
	; ix = this
	WriteLiteral:
		ld (0),a
	bufferPosition: equ $ - 2
		inc (ix + Inflate.bufferPosition)
		jr z,WriteLiteralCarry  ; unlikely
		jp hl
	WriteLiteralCarry:
		jp Inflate_WriteLiteralCarry
	bufferStart:
		db 0
	bufferEnd:
		db 0
	bufferEndCopyMargin:
		db 0
	state:
		db 0
	copyLength:
		dw 0
	copySource:
		dw 0
	reader:
		dw 0
	decoders:
		dw 0
	huffmanCodes:
		HuffmanCodes
	_size:
	ENDM

; bc = decoders buffer
; de = write buffer (32K, 256-byte aligned)
; hl = reader
; ix = this
; ix <- this
Inflate_Construct:
	ld a,e  ; check if write buffer is 256-byte aligned
	and a
	call nz,System_ThrowException
	ld (ix + Inflate.bufferStart),d
	ld (ix + Inflate.bufferPosition),0
	ld (ix + Inflate.bufferPosition + 1),d
	ld a,d
	add a,Inflate_BUFFER_SIZE >> 8
	ld (ix + Inflate.bufferEnd),a
	sub 3
	ld (ix + Inflate.bufferEndCopyMargin),a
	ld (ix + Inflate.state),0
	ld (ix + Inflate.reader),l
	ld (ix + Inflate.reader + 1),h
	ld (ix + Inflate.decoders),c
	ld (ix + Inflate.decoders + 1),b
	push ix
	call Inflate_GetHuffmanCodes
	call HuffmanCodes_Construct
	pop ix
	ret

; ix = this
; iy <- reader
; Modifies: de
Inflate_GetReaderIY:
	ld e,(ix + Inflate.reader)
	ld d,(ix + Inflate.reader + 1)
	ld iyl,e
	ld iyh,d
	ret

; ix = this
; ix <- decoders buffer
; Modifies: de
Inflate_GetDecoders:
	ld e,(ix + Inflate.decoders)
	ld d,(ix + Inflate.decoders + 1)
	ld ixl,e
	ld ixh,d
	ret

; ix = this
; ix <- huffman codes
; Modifies: de
Inflate_GetHuffmanCodes:
	ld de,Inflate.huffmanCodes
	add ix,de
	ret

; ix = this
; a <- >0: more data, 0: final data
; f <- nz: more data, z: final data
; de <- buffer address
; hl <- byte count
Inflate_Inflate:
	call Inflate_GetReaderIY
	call Inflate_InflateResume
	ld l,(ix + Inflate.bufferPosition)
	ld h,(ix + Inflate.bufferPosition + 1)
	ld e,0
	ld d,(ix + Inflate.bufferStart)
	ld (ix + Inflate.bufferPosition),e
	ld (ix + Inflate.bufferPosition + 1),d
	and a
	sbc hl,de
	ld a,(ix + Inflate.state)
	xor 1 << Inflate_STATE_FINAL_BIT
	ret

; ix = this
Inflate_InflateResume:
	bit Inflate_STATE_COMPRESSED_BIT,(ix + Inflate.state)
	jp nz,Inflate_InflateCompressed
	bit Inflate_STATE_COPY_BIT,(ix + Inflate.state)
	jp nz,Inflate_InflateUncompressed.Resume
	jp Inflate_InflateLoop

; ix = this
Inflate_InflateLoop:
	ld a,(ix + Inflate.state)
	and 1 << Inflate_STATE_FINAL_BIT
	ld (ix + Inflate.state),a
	ret nz
	call BitReader_Read_IY
	rla  ; carry to Inflate_STATE_FINAL_BIT
	ld (ix + Inflate.state),a
	ld b,2
	call BitReader_Read_N_IY
	and a
	jp z,Inflate_InflateUncompressed
	cp 2
	jp c,Inflate_InflateFixedCompressed
	jp z,Inflate_InflateDynamicCompressed
	jp System_ThrowException  ; invalid block type

; ix = this
; iy = reader
Inflate_InflateUncompressed: PROC
	set Inflate_STATE_COPY_BIT,(ix + Inflate.state)
	call BitReader_Align_IY
	call Reader_ReadWord_IY
	ld c,e
	ld b,d
	call Reader_ReadWord_IY
	ex de,hl
	scf
	adc hl,bc
	jp nz,System_ThrowException  ; invalid length
ResumeLoop:
	ld e,(ix + Inflate.bufferPosition)
	ld d,(ix + Inflate.bufferPosition + 1)
Loop:
	ld a,c
	or b
	jp z,Inflate_InflateLoop
	ld l,0
	ld h,(ix + Inflate.bufferEnd)
	sbc hl,de
	jr c,Suspend
	jr z,Suspend
	push bc
	sbc hl,bc
	jr nc,NoSplit  ; bc <= hl
	add hl,bc
	ld c,l
	ld b,h
NoSplit:
	call Reader_ReadBlockDirect_IY
	push bc
	call System_FastLDIR
	pop bc
	pop hl
	and a
	sbc hl,bc
	ld c,l
	ld b,h
	ld (ix + Inflate.bufferPosition),e
	ld (ix + Inflate.bufferPosition + 1),d
	jr Loop
Suspend:
	ld (ix + Inflate.copyLength),c
	ld (ix + Inflate.copyLength + 1),b
	ret
Resume:
	ld c,(ix + Inflate.copyLength)
	ld b,(ix + Inflate.copyLength + 1)
	jr ResumeLoop
	ENDP

; ix = this
; iy = reader
Inflate_InflateFixedCompressed:
	push ix
	call Inflate_GetHuffmanCodes
	call HuffmanCodes_BuildFixedDecoders
	pop ix
	jp Inflate_InflateCompressed

; ix = this
; iy = reader
Inflate_InflateDynamicCompressed:
	push ix
	call Inflate_GetHuffmanCodes
	call HuffmanCodes_BuildDynamicDecoders
	pop ix
	jp Inflate_InflateCompressed

; ix = this
; iy = reader
Inflate_InflateCompressed:
	push ix
	call Inflate_GetDecoders
	call Decoders_GetDecoders
	pop ix
	call BitReader_PrepareReadInline_IY
	call Inflate_Decode
	call BitReader_FinishReadInline_IY
	bit Inflate_STATE_COMPRESSED_BIT,(ix + Inflate.state)
	ret nz
	jp Inflate_InflateLoop

Inflate_Decode: PROC
	set Inflate_STATE_COMPRESSED_BIT,(ix + Inflate.state)
	bit Inflate_STATE_COPY_BIT,(ix + Inflate.state)
	jp nz,Inflate_CopySplitDestination.Resume
	Inflate_DecodeLiteralLengthInline
	ENDP

; c = inline bit reader state
; hl = literal/length decoder
; de = distance decoder
; ix = this
; iy = reader
Inflate_DecodeLiteralLengthInline: MACRO
	jp hl
	ENDM

; Literal/length alphabet symbols 0-255
; c = inline bit reader state
; hl = literal/length decoder
; de = distance decoder
; ix = this
; iy = reader
Inflate_WriteLiteral: REPT 256, ?value
	ld a,?value
	jp ix
	ENDM

; c = inline bit reader state
; hl = literal/length decoder
; de = distance decoder
; ix = this
; iy = reader
Inflate_WriteLiteralCarry:
	inc (ix + Inflate.bufferPosition + 1)
	ld a,(ix + Inflate.bufferPosition + 1)
	cp (ix + Inflate.bufferEnd)
	ret nc
	jp hl

; Literal/length alphabet symbol 256
; c = inline bit reader state
; hl = literal/length decoder
; de = distance decoder
; ix = this
; iy = reader
Inflate_EndBlock:
	res Inflate_STATE_COMPRESSED_BIT,(ix + Inflate.state)
	ret

; Literal/length alphabet symbols 257-285
; c = inline bit reader state
; hl = literal/length decoder
; de = distance decoder
; ix = this
; iy = reader
Inflate_CopyLength.0:
	exx
	ld bc,3
	Inflate_DecodeDistanceInline
Inflate_CopyLength.1:
	exx
	ld bc,4
	Inflate_DecodeDistanceInline
Inflate_CopyLength.2:
	exx
	ld bc,5
	Inflate_DecodeDistanceInline
Inflate_CopyLength.3:
	exx
	ld bc,6
	Inflate_DecodeDistanceInline
Inflate_CopyLength.4:
	exx
	ld bc,7
	Inflate_DecodeDistanceInline
Inflate_CopyLength.5:
	exx
	ld bc,8
	Inflate_DecodeDistanceInline
Inflate_CopyLength.6:
	exx
	ld bc,9
	Inflate_DecodeDistanceInline
Inflate_CopyLength.7:
	exx
	ld bc,10
	Inflate_DecodeDistanceInline
Inflate_CopyLength.8:
	call BitReader_ReadInline_1_IY
	add a,11
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.9:
	call BitReader_ReadInline_1_IY
	add a,13
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.10:
	call BitReader_ReadInline_1_IY
	add a,15
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.11:
	call BitReader_ReadInline_1_IY
	add a,17
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.12:
	call BitReader_ReadInline_2_IY
	add a,19
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.13:
	call BitReader_ReadInline_2_IY
	add a,23
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.14:
	call BitReader_ReadInline_2_IY
	add a,27
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.15:
	call BitReader_ReadInline_2_IY
	add a,31
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.16:
	call BitReader_ReadInline_3_IY
	add a,35
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.17:
	call BitReader_ReadInline_3_IY
	add a,43
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.18:
	call BitReader_ReadInline_3_IY
	add a,51
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.19:
	call BitReader_ReadInline_3_IY
	add a,59
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.20:
	call BitReader_ReadInline_4_IY
	add a,67
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.21:
	call BitReader_ReadInline_4_IY
	add a,83
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.22:
	call BitReader_ReadInline_4_IY
	add a,99
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.23:
	call BitReader_ReadInline_4_IY
	add a,115
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.24:
	call BitReader_ReadInline_5_IY
	add a,131
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.25:
	call BitReader_ReadInline_5_IY
	add a,163
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.26:
	call BitReader_ReadInline_5_IY
	add a,195
	jp Inflate_DecodeDistance_SetLength
Inflate_CopyLength.27:
	call BitReader_ReadInline_5_IY
	add a,227
	jp nc,Inflate_DecodeDistance_SetLength
	exx
	ld c,a
	ld b,1
	Inflate_DecodeDistanceInline
Inflate_CopyLength.28:
	exx
	ld bc,258
	Inflate_DecodeDistanceInline

; a = length
; c' = inline bit reader state
; hl' = literal/length decoder
; de' = distance decoder
; ix = this
; iy = reader
Inflate_DecodeDistance_SetLength:
	exx
	ld c,a
	ld b,0
	Inflate_DecodeDistanceInline

; bc = length
; c' = inline bit reader state
; hl' = literal/length decoder
; de' = distance decoder
; ix = this
; iy = reader
Inflate_DecodeDistanceInline: MACRO
	exx
	ex de,hl
	jp hl
	ENDM

; Distance alphabet symbols 0-29
; c = inline bit reader state
; bc = length
; de = literal/length decoder
; hl = distance decoder
; ix = this
; iy = reader
Inflate_CopyDistance.0:
	exx
	ld hl,-1
	jp Inflate_Copy
Inflate_CopyDistance.1:
	exx
	ld hl,-2
	jp Inflate_Copy
Inflate_CopyDistance.2:
	exx
	ld hl,-3
	jp Inflate_Copy
Inflate_CopyDistance.3:
	exx
	ld hl,-4
	jp Inflate_Copy
Inflate_CopyDistance.4:
	call BitReader_ReadInline_1_IY
	xor -5
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.5:
	call BitReader_ReadInline_1_IY
	xor -7
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.6:
	call BitReader_ReadInline_2_IY
	xor -9
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.7:
	call BitReader_ReadInline_2_IY
	xor -13
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.8:
	call BitReader_ReadInline_3_IY
	xor -17
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.9:
	call BitReader_ReadInline_3_IY
	xor -25
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.10:
	call BitReader_ReadInline_4_IY
	xor -33
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.11:
	call BitReader_ReadInline_4_IY
	xor -49
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.12:
	call BitReader_ReadInline_5_IY
	xor -65
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.13:
	call BitReader_ReadInline_5_IY
	xor -97
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.14:
	call BitReader_ReadInline_6_IY
	xor -129
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.15:
	call BitReader_ReadInline_6_IY
	xor -193
	jp Inflate_CopySmallDistance
Inflate_CopyDistance.16:
	call BitReader_ReadInline_7_IY
	exx
	cpl
	ld l,a
	ld h,-257 >> 8
	jp Inflate_Copy
Inflate_CopyDistance.17:
	call BitReader_ReadInline_7_IY
	exx
	xor -385 & 0FFH
	ld l,a
	ld h,-385 >> 8
	jp Inflate_Copy
Inflate_CopyDistance.18:
	call BitReader_ReadInline_8_IY
	exx
	cpl
	ld l,a
	ld h,-513 >> 8
	jp Inflate_Copy
Inflate_CopyDistance.19:
	call BitReader_ReadInline_8_IY
	exx
	cpl
	ld l,a
	ld h,-769 >> 8
	jp Inflate_Copy
Inflate_CopyDistance.20:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_1_IY
	xor -1025 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.21:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_1_IY
	xor -1537 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.22:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_2_IY
	xor -2049 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.23:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_2_IY
	xor -3073 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.24:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_3_IY
	xor -4097 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.25:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_3_IY
	xor -6145 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.26:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_4_IY
	xor -8193 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.27:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_4_IY
	xor -12289 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.28:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_5_IY
	xor -16385 >> 8
	jp Inflate_CopyLargeDistance
Inflate_CopyDistance.29:
	call BitReader_ReadInline_8_IY
	ex af,af'
	call BitReader_ReadInline_5_IY
	xor -24577 >> 8
	jp Inflate_CopyLargeDistance

; a = -distance
; bc = length
; c' = inline bit reader state
; de' = literal/length decoder
; hl' = distance decoder
; ix = this
; iy = reader
Inflate_CopySmallDistance:
	exx
	ld l,a
	ld h,-1
	jp Inflate_Copy

; a = -distance MSB
; a' = ~-distance LSB
; bc = length
; c' = inline bit reader state
; de' = literal/length decoder
; hl' = distance decoder
; ix = this
; iy = reader
Inflate_CopyLargeDistance:
	exx
	ld h,a
	ex af,af'
	cpl
	ld l,a
	jp Inflate_Copy

; bc = length
; hl = -distance
; c' = inline bit reader state
; de' = literal/length decoder
; hl' = distance decoder
; ix = this
; iy = reader
Inflate_Copy: PROC
	ld e,(ix + Inflate.bufferPosition)
	ld d,(ix + Inflate.bufferPosition + 1)
	add hl,de
	ld a,h
	jr nc,WrapSource
	cp (ix + Inflate.bufferStart)
	jr c,WrapSource
	ld a,(ix + Inflate.bufferEndCopyMargin)
	cp d  ; does the destination have a 512 byte margin without wrapping?
	jr c,Inflate_CopySplitDestination
Copy:
	ldi
	ldi
	ldir
Next:
	ld (ix + Inflate.bufferPosition),e
	ld (ix + Inflate.bufferPosition + 1),d
	exx
	ex de,hl
	Inflate_DecodeLiteralLengthInline
WrapSource:
	add a,Inflate_BUFFER_SIZE >> 8
	ld h,a
	ld a,(ix + Inflate.bufferEndCopyMargin)
	cp d  ; does the destination have a 512 byte margin without wrapping?
	jr c,Inflate_CopySplitDestination
	cp h  ; does the source have a 512 byte margin without wrapping?
	jp nc,Copy
	call Inflate_CopySplitSource
	jp Next
	ENDP

; bc = byte count
; de = destination
; hl = source
; ix = this
; bc <- 0
; de <- updated destination
; hl <- updated source
; Modifies: af
Inflate_CopySplitDestination: PROC
	ex de,hl
	add hl,bc
	jr c,Split
	ld a,h
	cp (ix + Inflate.bufferEnd)
	jr nc,Split
	and a
	sbc hl,bc
	ex de,hl
	call Inflate_CopySplitSource
	jp Inflate_Copy.Next
Split:
	push hl
	xor a
	sbc hl,bc
	sub l
	ld c,a
	ld a,(ix + Inflate.bufferEnd)
	sbc a,h
	ld b,a  ; bc = buffer end - source start
	ex de,hl
	call Inflate_CopySplitSource
	pop bc
	ld a,b
	sub (ix + Inflate.bufferEnd)
	ld b,a  ; bc = source end - buffer end
	or c
	jp z,SuspendLiteral
Suspend:
	set Inflate_STATE_COPY_BIT,(ix + Inflate.state)
	ld (ix + Inflate.copyLength),c
	ld (ix + Inflate.copyLength + 1),b
	ld (ix + Inflate.copySource),l
	ld (ix + Inflate.copySource + 1),h
SuspendLiteral:
	ld (ix + Inflate.bufferPosition),e
	ld (ix + Inflate.bufferPosition + 1),d
	exx
	ex de,hl
	ret
Resume:
	res Inflate_STATE_COPY_BIT,(ix + Inflate.state)
	ex de,hl
	exx
	ld c,(ix + Inflate.copyLength)
	ld b,(ix + Inflate.copyLength + 1)
	ld e,(ix + Inflate.bufferPosition)
	ld d,(ix + Inflate.bufferPosition + 1)
	ld l,(ix + Inflate.copySource)
	ld h,(ix + Inflate.copySource + 1)
	jp Inflate_CopySplitDestination
	ENDP

; bc = byte count
; de = destination
; hl = source
; ix = this
; bc <- 0
; de <- updated destination
; hl <- updated source
; Modifies: af
Inflate_CopySplitSource: PROC
	add hl,bc
	jr c,Split
	ld a,h
	cp (ix + Inflate.bufferEnd)
	jr nc,Split
	and a
	sbc hl,bc
	ldir
	ret
Split:
	push hl
	xor a
	sbc hl,bc
	sub l
	ld c,a
	ld a,(ix + Inflate.bufferEnd)
	sbc a,h
	ld b,a  ; bc = buffer end - source start
	ldir
	pop bc
	ld h,(ix + Inflate.bufferStart)
	ld a,b
	sub (ix + Inflate.bufferEnd)
	ld b,a  ; bc = source end - buffer end
	or c
	ret z
	ldir
	ret
	ENDP

;
Inflate_literalLengthSymbols:
	dw Inflate_WriteLiteral.0, Inflate_WriteLiteral.1, Inflate_WriteLiteral.2, Inflate_WriteLiteral.3
	dw Inflate_WriteLiteral.4, Inflate_WriteLiteral.5, Inflate_WriteLiteral.6, Inflate_WriteLiteral.7
	dw Inflate_WriteLiteral.8, Inflate_WriteLiteral.9, Inflate_WriteLiteral.10, Inflate_WriteLiteral.11
	dw Inflate_WriteLiteral.12, Inflate_WriteLiteral.13, Inflate_WriteLiteral.14, Inflate_WriteLiteral.15
	dw Inflate_WriteLiteral.16, Inflate_WriteLiteral.17, Inflate_WriteLiteral.18, Inflate_WriteLiteral.19
	dw Inflate_WriteLiteral.20, Inflate_WriteLiteral.21, Inflate_WriteLiteral.22, Inflate_WriteLiteral.23
	dw Inflate_WriteLiteral.24, Inflate_WriteLiteral.25, Inflate_WriteLiteral.26, Inflate_WriteLiteral.27
	dw Inflate_WriteLiteral.28, Inflate_WriteLiteral.29, Inflate_WriteLiteral.30, Inflate_WriteLiteral.31
	dw Inflate_WriteLiteral.32, Inflate_WriteLiteral.33, Inflate_WriteLiteral.34, Inflate_WriteLiteral.35
	dw Inflate_WriteLiteral.36, Inflate_WriteLiteral.37, Inflate_WriteLiteral.38, Inflate_WriteLiteral.39
	dw Inflate_WriteLiteral.40, Inflate_WriteLiteral.41, Inflate_WriteLiteral.42, Inflate_WriteLiteral.43
	dw Inflate_WriteLiteral.44, Inflate_WriteLiteral.45, Inflate_WriteLiteral.46, Inflate_WriteLiteral.47
	dw Inflate_WriteLiteral.48, Inflate_WriteLiteral.49, Inflate_WriteLiteral.50, Inflate_WriteLiteral.51
	dw Inflate_WriteLiteral.52, Inflate_WriteLiteral.53, Inflate_WriteLiteral.54, Inflate_WriteLiteral.55
	dw Inflate_WriteLiteral.56, Inflate_WriteLiteral.57, Inflate_WriteLiteral.58, Inflate_WriteLiteral.59
	dw Inflate_WriteLiteral.60, Inflate_WriteLiteral.61, Inflate_WriteLiteral.62, Inflate_WriteLiteral.63
	dw Inflate_WriteLiteral.64, Inflate_WriteLiteral.65, Inflate_WriteLiteral.66, Inflate_WriteLiteral.67
	dw Inflate_WriteLiteral.68, Inflate_WriteLiteral.69, Inflate_WriteLiteral.70, Inflate_WriteLiteral.71
	dw Inflate_WriteLiteral.72, Inflate_WriteLiteral.73, Inflate_WriteLiteral.74, Inflate_WriteLiteral.75
	dw Inflate_WriteLiteral.76, Inflate_WriteLiteral.77, Inflate_WriteLiteral.78, Inflate_WriteLiteral.79
	dw Inflate_WriteLiteral.80, Inflate_WriteLiteral.81, Inflate_WriteLiteral.82, Inflate_WriteLiteral.83
	dw Inflate_WriteLiteral.84, Inflate_WriteLiteral.85, Inflate_WriteLiteral.86, Inflate_WriteLiteral.87
	dw Inflate_WriteLiteral.88, Inflate_WriteLiteral.89, Inflate_WriteLiteral.90, Inflate_WriteLiteral.91
	dw Inflate_WriteLiteral.92, Inflate_WriteLiteral.93, Inflate_WriteLiteral.94, Inflate_WriteLiteral.95
	dw Inflate_WriteLiteral.96, Inflate_WriteLiteral.97, Inflate_WriteLiteral.98, Inflate_WriteLiteral.99
	dw Inflate_WriteLiteral.100, Inflate_WriteLiteral.101, Inflate_WriteLiteral.102, Inflate_WriteLiteral.103
	dw Inflate_WriteLiteral.104, Inflate_WriteLiteral.105, Inflate_WriteLiteral.106, Inflate_WriteLiteral.107
	dw Inflate_WriteLiteral.108, Inflate_WriteLiteral.109, Inflate_WriteLiteral.110, Inflate_WriteLiteral.111
	dw Inflate_WriteLiteral.112, Inflate_WriteLiteral.113, Inflate_WriteLiteral.114, Inflate_WriteLiteral.115
	dw Inflate_WriteLiteral.116, Inflate_WriteLiteral.117, Inflate_WriteLiteral.118, Inflate_WriteLiteral.119
	dw Inflate_WriteLiteral.120, Inflate_WriteLiteral.121, Inflate_WriteLiteral.122, Inflate_WriteLiteral.123
	dw Inflate_WriteLiteral.124, Inflate_WriteLiteral.125, Inflate_WriteLiteral.126, Inflate_WriteLiteral.127
	dw Inflate_WriteLiteral.128, Inflate_WriteLiteral.129, Inflate_WriteLiteral.130, Inflate_WriteLiteral.131
	dw Inflate_WriteLiteral.132, Inflate_WriteLiteral.133, Inflate_WriteLiteral.134, Inflate_WriteLiteral.135
	dw Inflate_WriteLiteral.136, Inflate_WriteLiteral.137, Inflate_WriteLiteral.138, Inflate_WriteLiteral.139
	dw Inflate_WriteLiteral.140, Inflate_WriteLiteral.141, Inflate_WriteLiteral.142, Inflate_WriteLiteral.143
	dw Inflate_WriteLiteral.144, Inflate_WriteLiteral.145, Inflate_WriteLiteral.146, Inflate_WriteLiteral.147
	dw Inflate_WriteLiteral.148, Inflate_WriteLiteral.149, Inflate_WriteLiteral.150, Inflate_WriteLiteral.151
	dw Inflate_WriteLiteral.152, Inflate_WriteLiteral.153, Inflate_WriteLiteral.154, Inflate_WriteLiteral.155
	dw Inflate_WriteLiteral.156, Inflate_WriteLiteral.157, Inflate_WriteLiteral.158, Inflate_WriteLiteral.159
	dw Inflate_WriteLiteral.160, Inflate_WriteLiteral.161, Inflate_WriteLiteral.162, Inflate_WriteLiteral.163
	dw Inflate_WriteLiteral.164, Inflate_WriteLiteral.165, Inflate_WriteLiteral.166, Inflate_WriteLiteral.167
	dw Inflate_WriteLiteral.168, Inflate_WriteLiteral.169, Inflate_WriteLiteral.170, Inflate_WriteLiteral.171
	dw Inflate_WriteLiteral.172, Inflate_WriteLiteral.173, Inflate_WriteLiteral.174, Inflate_WriteLiteral.175
	dw Inflate_WriteLiteral.176, Inflate_WriteLiteral.177, Inflate_WriteLiteral.178, Inflate_WriteLiteral.179
	dw Inflate_WriteLiteral.180, Inflate_WriteLiteral.181, Inflate_WriteLiteral.182, Inflate_WriteLiteral.183
	dw Inflate_WriteLiteral.184, Inflate_WriteLiteral.185, Inflate_WriteLiteral.186, Inflate_WriteLiteral.187
	dw Inflate_WriteLiteral.188, Inflate_WriteLiteral.189, Inflate_WriteLiteral.190, Inflate_WriteLiteral.191
	dw Inflate_WriteLiteral.192, Inflate_WriteLiteral.193, Inflate_WriteLiteral.194, Inflate_WriteLiteral.195
	dw Inflate_WriteLiteral.196, Inflate_WriteLiteral.197, Inflate_WriteLiteral.198, Inflate_WriteLiteral.199
	dw Inflate_WriteLiteral.200, Inflate_WriteLiteral.201, Inflate_WriteLiteral.202, Inflate_WriteLiteral.203
	dw Inflate_WriteLiteral.204, Inflate_WriteLiteral.205, Inflate_WriteLiteral.206, Inflate_WriteLiteral.207
	dw Inflate_WriteLiteral.208, Inflate_WriteLiteral.209, Inflate_WriteLiteral.210, Inflate_WriteLiteral.211
	dw Inflate_WriteLiteral.212, Inflate_WriteLiteral.213, Inflate_WriteLiteral.214, Inflate_WriteLiteral.215
	dw Inflate_WriteLiteral.216, Inflate_WriteLiteral.217, Inflate_WriteLiteral.218, Inflate_WriteLiteral.219
	dw Inflate_WriteLiteral.220, Inflate_WriteLiteral.221, Inflate_WriteLiteral.222, Inflate_WriteLiteral.223
	dw Inflate_WriteLiteral.224, Inflate_WriteLiteral.225, Inflate_WriteLiteral.226, Inflate_WriteLiteral.227
	dw Inflate_WriteLiteral.228, Inflate_WriteLiteral.229, Inflate_WriteLiteral.230, Inflate_WriteLiteral.231
	dw Inflate_WriteLiteral.232, Inflate_WriteLiteral.233, Inflate_WriteLiteral.234, Inflate_WriteLiteral.235
	dw Inflate_WriteLiteral.236, Inflate_WriteLiteral.237, Inflate_WriteLiteral.238, Inflate_WriteLiteral.239
	dw Inflate_WriteLiteral.240, Inflate_WriteLiteral.241, Inflate_WriteLiteral.242, Inflate_WriteLiteral.243
	dw Inflate_WriteLiteral.244, Inflate_WriteLiteral.245, Inflate_WriteLiteral.246, Inflate_WriteLiteral.247
	dw Inflate_WriteLiteral.248, Inflate_WriteLiteral.249, Inflate_WriteLiteral.250, Inflate_WriteLiteral.251
	dw Inflate_WriteLiteral.252, Inflate_WriteLiteral.253, Inflate_WriteLiteral.254, Inflate_WriteLiteral.255
	dw Inflate_EndBlock, Inflate_CopyLength.0, Inflate_CopyLength.1, Inflate_CopyLength.2
	dw Inflate_CopyLength.3, Inflate_CopyLength.4, Inflate_CopyLength.5, Inflate_CopyLength.6
	dw Inflate_CopyLength.7, Inflate_CopyLength.8, Inflate_CopyLength.9, Inflate_CopyLength.10
	dw Inflate_CopyLength.11, Inflate_CopyLength.12, Inflate_CopyLength.13, Inflate_CopyLength.14
	dw Inflate_CopyLength.15, Inflate_CopyLength.16, Inflate_CopyLength.17, Inflate_CopyLength.18
	dw Inflate_CopyLength.19, Inflate_CopyLength.20, Inflate_CopyLength.21, Inflate_CopyLength.22
	dw Inflate_CopyLength.23, Inflate_CopyLength.24, Inflate_CopyLength.25, Inflate_CopyLength.26
	dw Inflate_CopyLength.27, Inflate_CopyLength.28, System_ThrowException, System_ThrowException

Inflate_distanceSymbols:
	dw Inflate_CopyDistance.0, Inflate_CopyDistance.1, Inflate_CopyDistance.2, Inflate_CopyDistance.3
	dw Inflate_CopyDistance.4, Inflate_CopyDistance.5, Inflate_CopyDistance.6, Inflate_CopyDistance.7
	dw Inflate_CopyDistance.8, Inflate_CopyDistance.9, Inflate_CopyDistance.10, Inflate_CopyDistance.11
	dw Inflate_CopyDistance.12, Inflate_CopyDistance.13, Inflate_CopyDistance.14, Inflate_CopyDistance.15
	dw Inflate_CopyDistance.16, Inflate_CopyDistance.17, Inflate_CopyDistance.18, Inflate_CopyDistance.19
	dw Inflate_CopyDistance.20, Inflate_CopyDistance.21, Inflate_CopyDistance.22, Inflate_CopyDistance.23
	dw Inflate_CopyDistance.24, Inflate_CopyDistance.25, Inflate_CopyDistance.26, Inflate_CopyDistance.27
	dw Inflate_CopyDistance.28, Inflate_CopyDistance.29, System_ThrowException, System_ThrowException
