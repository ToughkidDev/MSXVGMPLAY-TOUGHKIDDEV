;
; The dynamic alphabets
;
HuffmanCodes_MAX_HEADERCODELENGTHS: equ 19
HuffmanCodes_MAX_LITERALLENGTHCODELENGTHS: equ 286
HuffmanCodes_MAX_DISTANCECODELENGTHS: equ 30
HuffmanCodes_FIXED_LITERALLENGTHCODELENGTHS: equ HuffmanCodes_MAX_LITERALLENGTHCODELENGTHS + 2
HuffmanCodes_FIXED_DISTANCECODELENGTHS: equ HuffmanCodes_MAX_DISTANCECODELENGTHS + 2

HuffmanCodes: MACRO
	alphabet:
		Alphabet
	literalLengthSymbols:
		dw 0
	distanceSymbols:
		dw 0
	decoders:
		dw 0
	hlit:
		db 0  ; we only store the LSB, MSB is always 1
	hdist:
		db 0
	hclen:
		db 0
	_size:
	ENDM

; bc = decoders buffer
; ix = this
HuffmanCodes_Construct:
	ld (ix + HuffmanCodes.decoders),c
	ld (ix + HuffmanCodes.decoders + 1),b
	ret

; ix = this
; iy = reader
; ix <- this
HuffmanCodes_BuildDynamicDecoders:
	call HuffmanCodes_ReadLengths
	call HuffmanCodes_ReadHeaderCodeLengths
	call HuffmanCodes_BuildHeaderCodeDecoder
	call HuffmanCodes_DecodeCodeLengths
	call HuffmanCodes_BuildLiteralLengthDecoder
	call HuffmanCodes_BuildDistanceDecoder
	ret

; ix = this
; ix <- this
HuffmanCodes_BuildFixedDecoders:
	ld bc,HuffmanCodes_fixedLiteralLengthCodeLengthsCount
	ld de,HuffmanCodes_fixedLiteralLengthCodeLengths
	ld hl,Inflate_literalLengthSymbols
	call Alphabet_Construct
	ld e,(ix + HuffmanCodes.decoders)
	ld d,(ix + HuffmanCodes.decoders + 1)
	call Decoders_GetLiteralLengthDecoder
	call Alphabet_BuildDecoder
	ld bc,HuffmanCodes_fixedDistanceCodeLengthsCount
	ld de,HuffmanCodes_fixedDistanceCodeLengths
	ld hl,Inflate_distanceSymbols
	call Alphabet_Construct
	ld e,(ix + HuffmanCodes.decoders)
	ld d,(ix + HuffmanCodes.decoders + 1)
	call Decoders_GetDistanceDecoder
	jp Alphabet_BuildDecoder

; ix = this
HuffmanCodes_BuildHeaderCodeDecoder:
	ld e,(ix + HuffmanCodes.decoders)
	ld d,(ix + HuffmanCodes.decoders + 1)
	push de
	ld bc,HuffmanCodes_MAX_HEADERCODELENGTHS
	ld hl,HuffmanCodes_headerCodeSymbols
	call Alphabet_Construct
	pop de
	call Decoders_GetDistanceDecoder
	jp Alphabet_BuildDecoder

; ix = this
HuffmanCodes_BuildLiteralLengthDecoder:
	ld e,(ix + HuffmanCodes.decoders)
	ld d,(ix + HuffmanCodes.decoders + 1)
	push de
	ld c,(ix + HuffmanCodes.hlit)
	ld b,1
	ld hl,Inflate_literalLengthSymbols
	call Alphabet_Construct
	pop de
	call Decoders_GetLiteralLengthDecoder
	jp Alphabet_BuildDecoder

; ix = this
HuffmanCodes_BuildDistanceDecoder:
	ld e,(ix + HuffmanCodes.decoders)
	ld d,(ix + HuffmanCodes.decoders + 1)
	push de
	ld hl,Decoders.distance
	add hl,de
	ex de,hl
	ld c,(ix + HuffmanCodes.hdist)
	ld b,0
	ld hl,Inflate_distanceSymbols
	call Alphabet_Construct
	pop de
	call Decoders_GetDistanceDecoder
	jp Alphabet_BuildDecoder

; ix = this
; iy = reader
HuffmanCodes_ReadLengths:
	ld b,5
	call BitReader_Read_N_IY
	inc a
	cp (HuffmanCodes_MAX_LITERALLENGTHCODELENGTHS & 0FFH) + 1
	call nc,System_ThrowException
	ld (ix + HuffmanCodes.hlit),a
	ld b,5
	call BitReader_Read_N_IY
	inc a
	cp HuffmanCodes_MAX_DISTANCECODELENGTHS + 1
	call nc,System_ThrowException
	ld (ix + HuffmanCodes.hdist),a
	ld b,4
	call BitReader_Read_N_IY
	add a,4
	cp HuffmanCodes_MAX_HEADERCODELENGTHS + 1
	call nc,System_ThrowException
	ld (ix + HuffmanCodes.hclen),a
	ret

; ix = this
; iy = reader
HuffmanCodes_ReadHeaderCodeLengths: PROC
	ld e,(ix + HuffmanCodes.decoders)
	ld d,(ix + HuffmanCodes.decoders + 1)
	push de
	ld l,e
	ld h,d
	inc de
	ld (hl),0
	ld bc,HuffmanCodes_MAX_HEADERCODELENGTHS - 1
	ldir
	pop de
	ld b,(ix + HuffmanCodes.hclen)
	ld hl,HuffmanCodes_headerCodeOrder
Loop:
	push bc
	ld b,3
	call BitReader_Read_N_IY
	ld c,(hl)  ; b = 0 after ReadBits
	inc hl
	ex de,hl
	add hl,bc
	ld (hl),a
	sbc hl,bc
	ex de,hl
	pop bc
	djnz Loop
	ret
	ENDP

; ix = this
; iy = reader
HuffmanCodes_DecodeCodeLengths:
	ld e,(ix + HuffmanCodes.decoders)
	ld d,(ix + HuffmanCodes.decoders + 1)
	ld hl,Decoders.distance
	add hl,de
	ex de,hl
	xor a
	sub (ix + HuffmanCodes.hlit)
	sub (ix + HuffmanCodes.hdist)
	push de
	push hl
	push ix
	ld ixl,e
	ld ixh,d
	ld e,a  ; range: 258-318, two 8-bit loops
	call BitReader_PrepareReadInline_IY
	call HuffmanCodes_DecodeCodeLength
	call HuffmanCodes_DecodeCodeLength
	call BitReader_FinishReadInline_IY
	ld a,e
	pop ix
	pop hl
	pop de
	and a
	call nz,System_ThrowException  ; code lengths count mismatch
	inc h
	cp (hl)
	call z,System_ThrowException  ; no end-of-block code
	ld c,(ix + HuffmanCodes.hlit)
	ld b,a
	add hl,bc
	ld c,(ix + HuffmanCodes.hdist)
	ldir
	ret

; c = inline bit reader state
; e = -code lengths remaining
; hl = code lengths address
; ix = header code decoder
; iy = reader
HuffmanCodes_DecodeCodeLength:
	equ System_JumpIX

; Header code alphabet symbols 0-15
; c = inline bit reader state
; e = -code lengths remaining
; hl = code lengths address
; ix = header code decoder
; iy = reader
HuffmanCodes_WriteLength: REPT 16, ?value
	ld (hl),?value
	jr HuffmanCodes_WriteAndNext
	ENDM

; c = inline bit reader state
; e = -code lengths remaining
; hl = code lengths address
; ix = header code decoder
; iy = reader
HuffmanCodes_WriteAndNext:
	inc hl
	inc e
	ret z
	jp ix

; Header code alphabet symbols 16
; c = inline bit reader state
; e = -code lengths remaining
; hl = code lengths address
; ix = header code decoder
; iy = reader
HuffmanCodes_Copy: PROC
	call BitReader_ReadInline_2_IY
	add a,3
	push bc
	ld b,a
	dec hl
	ld c,(hl)
	inc hl
Loop:
	ld (hl),c
	inc hl
	djnz Loop
	pop bc
	add a,e
	ld e,a
	ret c
	jp ix
	ENDP

; Header code alphabet symbols 17
; c = inline bit reader state
; e = -code lengths remaining
; hl = code lengths address
; ix = header code decoder
; iy = reader
HuffmanCodes_FillZero_3: PROC
	call BitReader_ReadInline_3_IY
	add a,3
Continue:
	push bc
	ld b,a
	ld c,0
Loop:
	ld (hl),c
	inc hl
	djnz Loop
	pop bc
	add a,e
	ld e,a
	ret c
	jp ix
	ENDP

; Header code alphabet symbols 18
; c = inline bit reader state
; e = -code lengths remaining
; hl = code lengths address
; ix = header code decoder
; iy = reader
HuffmanCodes_FillZero_11:
	call BitReader_ReadInline_7_IY
	add a,11
	jr HuffmanCodes_FillZero_3.Continue

;
HuffmanCodes_headerCodeOrder:
	db 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15

HuffmanCodes_headerCodeSymbols:
	dw HuffmanCodes_WriteLength.0, HuffmanCodes_WriteLength.1, HuffmanCodes_WriteLength.2, HuffmanCodes_WriteLength.3
	dw HuffmanCodes_WriteLength.4, HuffmanCodes_WriteLength.5, HuffmanCodes_WriteLength.6, HuffmanCodes_WriteLength.7
	dw HuffmanCodes_WriteLength.8, HuffmanCodes_WriteLength.9, HuffmanCodes_WriteLength.10, HuffmanCodes_WriteLength.11
	dw HuffmanCodes_WriteLength.12, HuffmanCodes_WriteLength.13, HuffmanCodes_WriteLength.14, HuffmanCodes_WriteLength.15
	dw HuffmanCodes_Copy, HuffmanCodes_FillZero_3, HuffmanCodes_FillZero_11, System_ThrowException

HuffmanCodes_fixedLiteralLengthCodeLengths:
	db 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8  ; 0-143: 8
	db 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
	db 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
	db 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
	db 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
	db 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
	db 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9  ; 144-255: 9
	db 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9
	db 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9
	db 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9
	db 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 7, 7, 7, 7, 7, 7, 7, 7  ; 256-279: 7
	db 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8  ; 280-287: 8

HuffmanCodes_fixedLiteralLengthCodeLengthsCount: equ $ - HuffmanCodes_fixedLiteralLengthCodeLengths

	IF HuffmanCodes_fixedLiteralLengthCodeLengthsCount != HuffmanCodes_FIXED_LITERALLENGTHCODELENGTHS
	ERROR "Fixed literal length code lengths count mismatch."
	ENDIF

HuffmanCodes_fixedDistanceCodeLengths:
	db 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5
	db 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5

HuffmanCodes_fixedDistanceCodeLengthsCount: equ $ - HuffmanCodes_fixedDistanceCodeLengths

	IF HuffmanCodes_fixedDistanceCodeLengthsCount != HuffmanCodes_FIXED_DISTANCECODELENGTHS
	ERROR "Fixed distance code lengths count mismatch."
	ENDIF
