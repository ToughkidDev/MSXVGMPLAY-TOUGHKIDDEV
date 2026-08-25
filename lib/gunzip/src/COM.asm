;
; Gzip file decompressor
;

	INCLUDE "Macros.asm"

GZIP_CRC32: equ 1
ZLIB_ADLER32: equ 1

	org 100H

READBUFFER_SIZE: equ 1000H
WRITEBUFFER_SIZE: equ 8000H
STACK_SIZE: equ 100H

TPA: ds 2E00H
RAM: ds 0100H
RAM_RESIDENT: equ RAM
READBUFFER: ds VIRTUAL READBUFFER_SIZE
WRITEBUFFER: ds VIRTUAL WRITEBUFFER_SIZE
DECODERBUFFER: ds VIRTUAL 1000H
TPA_TOP:

	SECTION TPA

	DOS2Runtime Application_Main

	INCLUDE "DOS.asm"
	INCLUDE "BIOS.asm"
	INCLUDE "System.asm"
	INCLUDE "DOS2Runtime.asm"
	INCLUDE "Application.asm"
	INCLUDE "CLI.asm"
	INCLUDE "GzipArchive.asm"
	INCLUDE "deflate/Inflate.asm"
	INCLUDE "deflate/Decoder.asm"
	INCLUDE "deflate/Alphabet.asm"
	INCLUDE "deflate/AlphabetTest.asm"
	INCLUDE "deflate/Branch.asm"
	INCLUDE "deflate/HuffmanCodes.asm"
	INCLUDE "Reader.asm"
	INCLUDE "BitReader.asm"
	INCLUDE "FileSupplier.asm"
	INCLUDE "CRC32Checker.asm"
	INCLUDE "CRC32CheckerTest.asm"

	IF GZIP_CRC32

	ALIGN 100H
CRC32Table:
	INCLUDE "crctable.asm"

	ENDIF

	ENDS
