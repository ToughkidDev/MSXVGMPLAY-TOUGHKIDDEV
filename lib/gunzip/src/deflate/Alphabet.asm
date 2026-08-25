;
; Huffman alphabet builder
;
Alphabet_MAX_CODELENGTH: equ 15
Alphabet_BRANCH_SIZE: equ 8
Alphabet_LEAF0_SIZE: equ 3

Alphabet: MACRO
	codeLengthCount:
		dw 0
	codeLengths:
		dw 0
	symbols:
		dw 0
	codeLengthCountsSum:
		dw 0
	codeLengthCounts:
		ds Alphabet_MAX_CODELENGTH * 2
	_size:
	ENDM

; bc = code length table length
; de = code length table
; hl = symbol handler table
; ix = this
; ix <- this
Alphabet_Construct:
	ld a,b
	or c
	call z,System_ThrowException
	ld (ix + Alphabet.codeLengthCount),c
	ld (ix + Alphabet.codeLengthCount + 1),b
	ld (ix + Alphabet.codeLengths),e
	ld (ix + Alphabet.codeLengths + 1),d
	ld (ix + Alphabet.symbols),l
	ld (ix + Alphabet.symbols + 1),h
	call Alphabet_CountCodeLengths
	call Alphabet_CheckCodeComplete
	ret

; ix = this
Alphabet_CountCodeLengths: PROC
	ld e,(ix + Alphabet.codeLengthCount)
	ld d,(ix + Alphabet.codeLengthCount + 1)
	ld l,(ix + Alphabet.codeLengths)
	ld h,(ix + Alphabet.codeLengths + 1)
	ld b,e  ; convert 16-bit counter de to two 8-bit counters in b and c
	dec de
	inc d
	ld c,d
	exx
	ld e,ixl
	ld d,ixh
	ld hl,Alphabet.codeLengthCounts
	add hl,de
	ld e,l
	ld d,h
	inc de
	ld (hl),0
	ld bc,Alphabet_MAX_CODELENGTH * 2 - 1
	ldir
	ld hl,-Alphabet_MAX_CODELENGTH * 2 - 2
	add hl,de
	ex de,hl  ; de = ix + Alphabet.codeLengthCounts - 2
	ld bc,0
	exx
Loop:
	ld a,(hl)
	inc hl
	and a
	jr z,Skip
	cp Alphabet_MAX_CODELENGTH + 1
	call nc,System_ThrowException
	exx
	inc bc
	add a,a
	ld l,a
	ld h,0
	add hl,de
	inc (hl)
	jr z,Overflow
OverflowContinue:
	exx
Skip:
	djnz Loop
	dec c
	jr nz,Loop
	exx
	ld (ix + Alphabet.codeLengthCountsSum),c
	ld (ix + Alphabet.codeLengthCountsSum + 1),b
	exx
	ret
Overflow:
	inc hl
	inc (hl)
	jp OverflowContinue
	ENDP

; ix = this
Alphabet_CheckCodeComplete: PROC
	push ix
	ld hl,1
	ld b,Alphabet_MAX_CODELENGTH
Loop:
	ld e,(ix + Alphabet.codeLengthCounts)
	ld d,(ix + Alphabet.codeLengthCounts + 1)
	add hl,hl
	sbc hl,de
	call c,System_ThrowException  ; over-full Huffman code
	inc ix
	inc ix
	djnz Loop
	pop ix
	ret z  ; complete
	ld l,(ix + Alphabet.codeLengthCountsSum)
	ld h,(ix + Alphabet.codeLengthCountsSum + 1)
	ld e,(ix + Alphabet.codeLengthCounts)
	ld d,(ix + Alphabet.codeLengthCounts + 1)
	sbc hl,de
	ret z  ; empty code or one-symbol code
	call System_ThrowException  ; under-full Huffman code
	ENDP

; bc = decoder buffer end
; de = decoder buffer
; hl = sorted code lengths start
; ix = this
Alphabet_BuildDecoder:
	push bc
	push de
	push hl
	call Alphabet_InitCodeLengthsTable
	call Alphabet_SortCodeLengths
	pop hl
	pop de
	pop bc
	call Alphabet_BuildTree
	ret

; hl = sorted code lengths start address
; ix = this
Alphabet_InitCodeLengthsTable: PROC
	ld b,Alphabet_MAX_CODELENGTH
	push ix
Loop:
	ld e,(ix + Alphabet.codeLengthCounts)
	ld d,(ix + Alphabet.codeLengthCounts + 1)
	ld (ix + Alphabet.codeLengthCounts),l
	ld (ix + Alphabet.codeLengthCounts + 1),h
	inc ix
	inc ix
	add hl,de
	add hl,de
	add hl,de
	djnz Loop
	ld (hl),0
	pop ix
	ret
	ENDP

; Generate list of (code length, symbol) pairs, sorted by code length
; ix = this
Alphabet_SortCodeLengths: PROC
	exx
	ld l,(ix + Alphabet.symbols)
	ld h,(ix + Alphabet.symbols + 1)
	exx
	ld l,(ix + Alphabet.codeLengths)
	ld h,(ix + Alphabet.codeLengths + 1)
	ld e,(ix + Alphabet.codeLengthCount)
	ld d,(ix + Alphabet.codeLengthCount + 1)
	ld b,e  ; convert 16-bit counter de to two 8-bit counters in b and c
	dec de
	inc d
	ld c,d
Loop:
	ld a,(hl)
	inc hl
	add a,a
	jr z,Skip
	exx
	ld e,a
	ld d,0
	push ix
	add ix,de
	ld e,(ix + Alphabet.codeLengthCounts - 2)
	ld d,(ix + Alphabet.codeLengthCounts - 1)
	rrca
	ld (de),a
	inc de
	ldi
	ldi
	ld (ix + Alphabet.codeLengthCounts - 2),e
	ld (ix + Alphabet.codeLengthCounts - 1),d
	pop ix
	exx
SkipContinue:
	djnz Loop
	dec c
	jr nz,Loop
	ret
Skip:
	exx
	inc hl
	inc hl
	exx
	jp SkipContinue
	ENDP

; bc = decoder buffer end
; de = decoder buffer
; hl = sorted code lengths
; ix = this
Alphabet_BuildTree: PROC
	push bc
	ld c,0
	call Alphabet_GetNextSymbol
	jp z,TrapEmptyTree
	call Alphabet_BuildBranch
	call nz,System_ThrowException  ; over-full Huffman code
	pop hl
	and a
	sbc hl,de
	call c,System_ThrowException
	ret
TrapEmptyTree:
	pop bc
	ex de,hl
	ld (hl),0C3H  ; jp
	inc hl
	ld (hl),System_ThrowException & 0FFH
	inc hl
	ld (hl),System_ThrowException >> 8
	ret
	ENDP

; b = bits left
; c = code length
; de = tree position
; hl = sorted (code length, symbol) list pointer
; ix = this
; f <- c: end reached, z: no bits left
Alphabet_BuildBranch:
	push iy
	ld iyl,e
	ld iyh,d
	push bc
	push hl
	ld hl,Branch_template
	REPT Alphabet_BRANCH_SIZE
	ldi
	ENDM
	pop hl
	pop bc
	call Alphabet_BuildBranchZero
	call nc,Alphabet_BuildBranchOne
	pop iy
	ret

; b = bits left
; c = code length
; de = tree position
; hl = sorted (code length, symbol) list pointer
; iy = current branch
; ix = this
; f <- c: end reached, z: no bits left
Alphabet_BuildBranchZero: PROC
	djnz Branch
Leaf:
	ld a,0C3H  ; jp
	ld (de),a
	inc de
	inc hl
	ldi
	ldi
	inc bc
	inc bc
	call Alphabet_GetNextSymbol
	inc b
	ret
Branch:
	call Alphabet_BuildBranch
	inc b
	ret
	ENDP

; b = bits left
; c = code length
; de = tree position
; hl = sorted (code length, symbol) list pointer
; iy = current branch
; ix = this
; f <- c: end reached, z: no bits left
Alphabet_BuildBranchOne: PROC
	djnz Branch
Leaf:
	inc hl
	ld a,(hl)
	inc hl
	ld (iy + Branch.jumpAddress),a
	ld a,(hl)
	inc hl
	ld (iy + Branch.jumpAddress + 1),a
	call Alphabet_GetNextSymbol
	inc b
	ret
Branch:
	ld (iy + Branch.jumpAddress),e
	ld (iy + Branch.jumpAddress + 1),d
	call Alphabet_BuildBranch
	inc b
	ret
	ENDP

; c = code length
; hl = sorted (code length, symbol) list pointer
; ix = this
; b <- bits left
; c <- new code length
; f <- c: negative bits left, z: no bits left
Alphabet_GetNextSymbol:
	ld a,(hl)
	sub c
	ld c,(hl)
	ld b,a
	ret
