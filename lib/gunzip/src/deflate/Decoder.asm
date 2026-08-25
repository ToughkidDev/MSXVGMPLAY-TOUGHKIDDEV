;
; Huffman decoder buffers
;
; The size of the decoder depends on the number of branches in the binary decoding
; tree, and the number of leaves that are in the zero-position of a branch.
;
; The number of branches is easy to determine; given that the canonical Huffman
; code used by DEFLATE is complete, the number of branches will be one less than
; the number of symbols. Each branch needs 8 bytes.
;
; The number of leaves for codewords which end on a 0 equals the sum of the
; number of leaves for each codeword bit length class, divided by two, rounded up.
; This is because each new bit level starts with a 0 as the least significant bit.
; Each zero-leaf needs 3 bytes.
;
; The best case number of zero-leaves is therefore when each bit level has an even
; number of leaves, which equals half the number of symbols rounded up. And the
; worst case is when each has an odd number of leaves, except for the deepest
; level (15th bit) which must be even for the Huffman code to be complete.
;
; The zero-leaf count for codes of 19 symbols (header code lengths) is 10 best
; case and 16 worst case. Worst decoder size is thus 192 bytes.
;
; The zero-leaf count for codes of 30 symbols (distance code lengths) is 15 best
; case and 21 worst case. Worst decoder size is thus 295 bytes.
;
; The zero-leaf count for codes of 286 symbols (literal/length code lengths) is
; 143 best case and 149 worst case. Worst decoder size is thus 2727 bytes.
;
; As you can see for larger alphabets the worst case is always 6 more zero-leaves
; than the best case. This is because of the 15 usable bit levels, the last one
; must be even, and one other must be zero in order to represent more than 16
; symbols. This leaves 13 bit levels, and since it takes two odd counts to replace
; one even count, we can have at most six more of them.
;
Decoder: MACRO ?symbols
	decoder:
		ds (?symbols - 1) * Alphabet_BRANCH_SIZE + ((?symbols + 1 >> 1) + 6) * Alphabet_LEAF0_SIZE
	decoderEnd:
		ds 4
	sortedCodeLengths: equ $ - (3 * ?symbols + 1)
	ENDM

Decoders: MACRO
	literalLength:
		Decoder HuffmanCodes_FIXED_LITERALLENGTHCODELENGTHS
	distance:
		Decoder HuffmanCodes_FIXED_DISTANCECODELENGTHS
	_size:
	ENDM

; ix = this
; hl <- literal/length decoder
; de <- distance decoder
Decoders_GetDecoders:
	ld e,ixl
	ld d,ixh
	ld hl,Decoders.distance
	add hl,de
	ex de,hl
	ret

; bc = decoder buffer end
; de = decoder buffer
; hl = sorted code lengths start
; de = this
Decoders_GetLiteralLengthDecoder:
	ld hl,Decoders.literalLength.decoderEnd
	add hl,de
	ld c,l
	ld b,h
	ld hl,Decoders.literalLength.sortedCodeLengths
	add hl,de
	ret

; bc = decoder buffer end
; de = decoder buffer
; hl = sorted code lengths start
; de = this
Decoders_GetDistanceDecoder:
	ld hl,Decoders.distance.decoderEnd
	add hl,de
	ld c,l
	ld b,h
	ld hl,Decoders.distance.sortedCodeLengths
	add hl,de
	push hl
	ld hl,Decoders.distance
	add hl,de
	ex de,hl
	pop hl
	ret
