;
; Huffman tree node
;
Branch: MACRO
	; iy = reader
	Process:
		BitReader_ReadInline_IY
	jump:
		jp c,System_ThrowException
	jumpAddress: equ $ - 2
	_size:
	ENDM

Branch_template: Branch

	IF Alphabet_BRANCH_SIZE != Branch._size
	ERROR "Branch size mismatch."
	ENDIF
