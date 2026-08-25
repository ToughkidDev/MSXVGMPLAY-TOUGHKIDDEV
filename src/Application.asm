;
; Top-level application program class
;
Application_VGMREADER_BASE_ADDRESS: equ 8000H

Application: MACRO
	freebieSegment:
		MapperSegment
	gzipStreamActive:
		db 0
	cli:
		CLI
	mappedBufferFactory:
		StaticFactory MappedBuffer_instance, MappedBuffer_Construct, MappedBuffer_Destruct
	reader:
		MappedReader
	streamLoader:
		StreamLoader
	drivers:
		Drivers
	vgm:
		VGM
	vgmFactory:
		StaticFactory vgm, VGM_Construct, VGM_Destruct
	player:
		Player
	playerFactory:
		StaticFactory player, Player_Construct, Player_Destruct
	_size:
	ENDM

;
Application_Main:
	ld ix,Mapper_instance
	call Mapper_Construct

	ld hl,Application_MainContinue
	call System_TryCall

	ld ix,Mapper_instance
	call Mapper_Destruct
	jp System_Rethrow

Application_MainContinue:
	call Application_CheckStack

	call VDP_InitMirrorsOnVDPUpgrades

	ld hl,Application_welcome
	call System_Print

	ld ix,Heap_main
	call Heap_Construct
	ld bc,HEAP_SIZE
	ld de,HEAP
	call Heap_Free

	call Player_InitCommandsJumpTable

	ld ix,Application_instance
	call Application_Construct

	push ix
	ld hl,Application_EnterMainLoop
	call System_TryCall
	pop ix

	call Application_Destruct

	call System_Rethrow
	jp Application_CheckMemoryLeak

; ix = this
; ix <- this
Application_Construct:
	ld (ix + Application.gzipStreamActive),0
	ld h,80H
	call Mapper_instance.GetPH
	ld (ix + Application.freebieSegment + MapperSegment.segment),a
	call Memory_GetSlot
	ld (ix + Application.freebieSegment + MapperSegment.slot),a
	push ix
	call Application_GetCLI
	call CLI_Construct
	pop ix
	push ix
	call Application_GetDrivers
	call Drivers_Construct
	pop ix
	ret

; ix = this
; ix <- this
Application_Destruct:
	push ix
	call Application_GetPlayerFactory
	call StaticFactory_Destroy
	pop ix
	push ix
	call Application_GetVGMFactory
	call StaticFactory_Destroy
	pop ix
	push ix
	call Application_GetMappedBufferFactory
	call StaticFactory_Destroy
	pop ix
	push ix
	call Application_GetCLI
	call CLI_Destruct
	pop ix
	push ix
	call Application_GetDrivers
	call Drivers_Destruct
	pop ix
	ret

; ix = this
; ix <- Command-line interface
Application_GetCLI:
	ld de,Application.cli
	add ix,de
	ret

; ix = this
; ix <- mapped buffer factory
Application_GetMappedBufferFactory:
	ld de,Application.mappedBufferFactory
	add ix,de
	ret

; ix = this
; ix <- reader
Application_GetReader:
	ld de,Application.reader
	add ix,de
	ret

; ix = this
; ix <- stream loader
Application_GetStreamLoader:
	ld de,Application.streamLoader
	add ix,de
	ret

; ix = this
; ix <- driver manager
Application_GetDrivers:
	ld de,Application.drivers
	add ix,de
	ret

; ix = this
; ix <- VGM
Application_GetVGM:
	ld de,Application.vgm
	add ix,de
	ret

; ix = this
; ix <- VGM factory
Application_GetVGMFactory:
	ld de,Application.vgmFactory
	add ix,de
	ret

; ix = this
; ix <- player
Application_GetPlayer:
	ld de,Application.player
	add ix,de
	ret

; ix = this
; ix <- player factory
Application_GetPlayerFactory:
	ld de,Application.playerFactory
	add ix,de
	ret

; ix = this
Application_EnterMainLoop:
	call Application_CheckUsageInstructions
	call Application_PrintLoading
	call Application_ConstructMappedBuffer
	call Application_IsVGZ
	jr nz,Application_EnterMainLoopPlainVGM
	call Application_StreamLoadVGZ
	jr Application_EnterMainLoopAfterStreamLoad

	; Plain .vgm: stream directly from disk. PCM data blocks are diverted
	; straight into sound chip memory as they are encountered and never
	; occupy system RAM; only the (much smaller) register/wait command
	; stream ends up in the mapped buffer that gets played back.

Application_EnterMainLoopPlainVGM:
	call Application_StreamLoadVGM
	jr Application_EnterMainLoopAfterStreamLoad

; A .vgz uses the same compact-command-buffer pipeline as a plain .vgm.
; GzipStreamReader expands only a small relay at a time while PCM blocks are
; immediately copied to the selected sound cartridge.
Application_StreamLoadVGZ:
	call Application_OpenAndConstructGzipStreamLoader
	ld (ix + Application.gzipStreamActive),0FFH
	push ix
	ld hl,Application_ConstructAndRunGzipStreamLoader
	call System_TryCall
	pop ix
	call System_HasException
	jr z,Application_StreamLoadVGZ_ReadyToPlay
	call Application_DestructGzipStreamLoader
	jp System_Rethrow
Application_StreamLoadVGZ_ReadyToPlay:
	ret

Application_EnterMainLoopAfterStreamLoad:
	call Application_PrintStreamingVGMHardwareInfo
	call Application_ConstructPlayer
	jp Application_Play

; ix = this
Application_CheckUsageInstructions:
	push ix
	call Application_GetCLI
	call CLI_GetFileInfoBlock
	ld hl,Application_usageInstructions
	call z,System_ThrowExceptionWithMessage
	pop ix
	ret

; Streams a plain .vgm file directly from disk (see StreamLoader.asm):
; opens the file, reads the header, prints track info, constructs the VGM
; (and its chips) from that header, then runs the single-pass scan that
; diverts PCM data blocks straight to chip memory and copies everything
; else into the compact command buffer. The file is closed again as soon
; as this finishes, whether it succeeds or throws.
; ix = this
Application_StreamLoadVGM: PROC
	call Application_OpenAndConstructStreamLoader
	push ix
	ld hl,Application_ConstructAndRunStreamLoader
	call System_TryCall
	pop ix
	call Application_DestructStreamLoader
	; StreamFileReader_class.Delete leaves IX at the freed reader object.
	; The caller immediately continues into Application_ConstructPlayer, so
	; restore the application singleton before returning on both success and
	; exception paths.
	ld ix,Application_instance
	jp System_Rethrow
	ENDP

; ix = this
Application_ConstructAndRunStreamLoader:
	call Application_ConstructVGMFromStreamLoader
	jp Application_RunStreamLoader

; ix = this
Application_ConstructAndRunGzipStreamLoader:
	call Application_ConstructVGMFromStreamLoader
	push ix
	call Application_GetStreamLoader
	call StreamLoader_RunFromCurrentPosition
	pop ix
	; The streaming reader/driver callbacks may use IX as private state.
	; Metadata lookup is application-owned, so reacquire the singleton instead
	; of relying on the callback's incoming register value.
	ld ix,Application_instance
	call Application_PrintGzipGD3FromCurrentPosition
	ret

; The gzip reader is forward-only.  In a valid VGM, GD3 immediately follows
; the end marker, so read it from the current stream position before playback.
; GD3 is deliberately not copied to the compact playback buffer.
; ix = this
Application_PrintGzipGD3FromCurrentPosition: PROC
	push ix
	call Application_GetStreamLoader
	push ix
	call StreamLoader_GetHeader
	call Header_GetGD3Offset                  ; z = no GD3 tag
	pop ix                                    ; ix = StreamLoader
	jr z,Done

	push ix
	call StreamLoader_GetReader_IY
	pop ix
	call System_PrintCrLf
	call GD3_PrintInfoEnglish_Continue
	call System_PrintCrLf
Done:
	pop ix
	ret
	ENDP

; Allocates a StreamFileReader from the heap and wires it into the
; StreamLoader, opens the file, wires the compact command buffer writer to
; the mapped buffer, reads the 256-byte header directly from the file, and
; prints the GD3 tag and header info - all before anything is written to
; system RAM other than the header snapshot itself.
; ix = this (ignored internally in favour of the well-known Application_
; instance singleton - there is exactly one for the process's lifetime -
; to keep this straightforward)
Application_OpenAndConstructStreamLoader: PROC
	call StreamFileReader_class.New       ; ix = initialized reader instance
	push ix
	pop de
	push de                               ; [readerAddr]
	ld ix,Application_instance
	call Application_GetStreamLoader
	pop de                                   ; de = readerAddr ; ix = streamLoader
	call StreamLoader_SetReader

	ld ix,Application_instance
	call Application_GetCLI
	call CLI_GetFileInfoBlock                    ; ix <- FileInfoBlock
	push ix
	pop hl                                      ; hl = FileInfoBlock (original loader convention)

	ld ix,Application_instance
	call Application_GetStreamLoader
	call StreamLoader_GetReader                 ; ix <- reader instance
	call StreamFileReader_Construct                ; hl=FileInfoBlock, ix=reader

	ld ix,Application_instance
	call Application_GetStreamLoader
	ld de,MappedBuffer_instance
	call StreamLoader_Construct                       ; de=mappedbuffer, ix=streamLoader
	call StreamLoader_ReadHeaderAndPrintTag
	ld ix,Application_instance
	ret
	ENDP

; Constructs the mapped reader over the (about to be populated) compact
; buffer, and the VGM object - including detecting and connecting all sound
; chips - using the header StreamLoader already parsed.
; ix = this
Application_ConstructVGMFromStreamLoader: PROC
	push ix                              ; [A]
	push ix                                ; [A,A]
	call Application_GetDrivers             ; ix = drivers
	ex (sp),ix                                ; [A,drivers], ix = A
	push ix                                     ; [A,drivers,A]
	call Application_GetReader                    ; ix = reader
	ld de,MappedBuffer_instance
	ld hl,Application_VGMREADER_BASE_ADDRESS
	call MappedReader_Construct                     ; ix = reader (unchanged)
	ex (sp),ix                                        ; [A,drivers,reader], ix = A
	push ix                                             ; [A,drivers,reader,A]
	call Application_GetStreamLoader                      ; ix = streamLoader
	call StreamLoader_GetHeader                             ; ix = header
	ex (sp),ix                                                ; [A,drivers,reader,header], ix = A
	call Application_GetVGM                                     ; ix = vgm
	pop iy                                                        ; iy = header
	pop de                                                          ; de = reader
	pop hl                                                            ; hl = drivers
	call VGM_ConstructFromHeader                                        ; ix=vgm,de=reader,hl=drivers,iy=header
	; A streaming gzip command buffer is still empty here.  VGM_PrintInfo
	; follows the GD3 offset through MappedReader, so it must not run until
	; StreamLoader has populated the compact buffer.
	pop ix                                                                ; ix = A
	; VGM was constructed by hand (not via StaticFactory_Create), so mark
	; the factory as constructed ourselves - Application_Destruct relies on
	; this flag to know it must call VGM_Destruct later.
	push ix
	call Application_GetVGMFactory
	ld (ix + StaticFactory.constructed),1
	pop ix
	ret
	ENDP

; GD3 metadata is printed while the stream is still positioned at its tag.
; Print the remaining original VGM info only after the scan: it needs neither
; a seek nor GD3 bytes in the compact command buffer, and includes the active
; chip-to-driver mapping that users rely on to verify their cartridge setup.
; ix = this
Application_PrintStreamingVGMHardwareInfo: PROC
	push ix
	call Application_GetVGM
	call VGM_PrintHardwareInfo
	pop ix
	ret
	ENDP

; ix = this
Application_RunStreamLoader: PROC
	push ix
	call Application_GetStreamLoader
	call StreamLoader_Run
	pop ix
	ret
	ENDP

; ix = this (ignored, see Application_OpenAndConstructStreamLoader)
Application_DestructStreamLoader: PROC
	ld ix,Application_instance
	call Application_GetStreamLoader
	call StreamLoader_GetReader        ; ix <- reader (StreamFileReader)
	push ix                              ; [reader]
	call StreamFileReader_Destruct
	pop ix
	jp StreamFileReader_class.Delete
	ENDP

; Opens a gzip reader after allocating the first command-buffer segment.
; The gzip inflater temporarily replaces pages 1 and 2; its restore step
; needs a currently selected command-buffer segment to put page 2 back.
; ix = this
Application_OpenAndConstructGzipStreamLoader: PROC
	; GzipStreamReader embeds self-modifying Reader/FileSupplier/Inflate
	; routines.  Allocate a copied template, not raw heap bytes.
	call GzipStreamReader_class.New
	push ix
	pop de
	push de
	ld ix,Application_instance
	call Application_GetStreamLoader
	pop de
	call StreamLoader_SetReader

	ld ix,Application_instance
	call Application_GetCLI
	call CLI_GetFileInfoBlock
	push ix
	pop hl                                      ; hl = FileInfoBlock
	push hl                                      ; preserve FileInfoBlock

	; Keep both arguments across the accessors below: each accessor uses DE
	; as scratch, so loading the CommandWriter pointer before obtaining the
	; reader silently replaced it with the reader pointer.  RestorePages then
	; selected page 2 through that invalid "writer", corrupting the mapper.
	ld ix,Application_instance
	call Application_GetStreamLoader
	call StreamLoader_GetReader
	push ix                                      ; preserve reader instance

	ld ix,Application_instance
	call Application_GetStreamLoader
	call StreamLoader_GetWriter
	push ix
	pop de                                      ; de = CommandWriter
	pop ix                                      ; ix = GzipStreamReader
	pop hl                                      ; hl = FileInfoBlock
	call GzipStreamReader_Construct

	; Allocate the StreamLoader header only after the inflater's decoder
	; workspace.  The original loader uses this order; apart from matching its
	; heap layout it keeps the generated Huffman decode tables below all of the
	; StreamLoader-owned state.
	ld ix,Application_instance
	call Application_GetStreamLoader
	ld de,MappedBuffer_instance
	call StreamLoader_Construct

	; The inflater now owns the original freebie segment.  Allocate and pad an
	; independent CommandWriter segment only after that transfer.
	ld ix,Application_instance
	call Application_GetStreamLoader
	call StreamLoader_PadBuffer

	ld ix,Application_instance
	call Application_GetStreamLoader
	call StreamLoader_ReadGzipHeaderAndPosition
	ld ix,Application_instance
	ret
	ENDP

; ix = this
Application_DestructGzipStreamLoader: PROC
	ld a,(ix + Application.gzipStreamActive)
	or a
	ret z
	push ix
	ld ix,Application_instance
	call Application_GetStreamLoader
	call StreamLoader_GetReader
	push ix
	call GzipStreamReader_Destruct
	pop ix
	call GzipStreamReader_class.Delete
	pop ix
	ld (ix + Application.gzipStreamActive),0
	ret
	ENDP

; ix = this
Application_ConstructVGM:
	push ix
	push ix
	call Application_GetDrivers
	ex (sp),ix
	push ix
	call Application_GetReader
	ld de,MappedBuffer_instance
	ld hl,Application_VGMREADER_BASE_ADDRESS
	call MappedReader_Construct
	ex (sp),ix
	call Application_GetVGMFactory
	pop de
	pop hl
	call StaticFactory_Create
	call VGM_PrintInfo
	pop ix
	ret

Application_LoadDataBlocks:
	push ix
	call Application_GetPlayer
	call Player_HasDataBlocks
	ld hl,Application_loadingSamples
	call z,System_Print
	call z,Player_LoadDataBlocks
	pop ix
	ret

; ix = this
Application_ConstructMappedBuffer:
	push ix
	ld a,(ix + Application.freebieSegment + MapperSegment.segment)
	ld b,(ix + Application.freebieSegment + MapperSegment.slot)
	call Application_GetMappedBufferFactory
	call StaticFactory_Create
	pop ix
	ret

; ix = this
; f <- z: is vgz
Application_IsVGZ:
	push ix
	call Application_GetCLI
	call CLI_GetFileInfoBlock
	call FileInfoBlock_GetName
	pop ix
	ld a,0
	ld bc,256
	cpir
	dec hl
	dec hl
	ld a,(hl)
	and 11011111B  ; upper-case
	cp "Z"
	ret nz
	dec hl
	ld a,(hl)
	and 11011111B  ; upper-case
	cp "G"
	ret nz
	dec hl
	ld a,(hl)
	and 11011111B  ; upper-case
	cp "V"
	ret nz
	dec hl
	ld a,(hl)
	cp "."
	ret

; ix = this
Application_PrintLoading:
	ld hl,Application_loadingFile
	call System_Print
	push ix
	call Application_GetCLI
	call CLI_GetFileInfoBlock
	call FileInfoBlock_GetName
	pop ix
	call System_Print
	ld hl,Application_dotDotDot
	jp System_Print

; ix = this
Application_ConstructPlayer:
	push ix
	call Application_GetCLI
	ld a,(ix + CLI.loops)
	pop ix
	push ix
	push ix
	call Application_GetVGM
	ex (sp),ix
	call Application_GetPlayerFactory
	pop de
	call StaticFactory_Create
	pop ix
	ret

; ix = this
Application_Play:
	ld hl,Application_playing
	call System_Print
	call Application_EnterBlackout
	push ix
	call Application_GetPlayer
	ld hl,Player_Play
	call System_TryCall
	pop ix
	call Application_DestructGzipStreamLoader
	jp Application_ExitBlackout

; If enabled, blacks out the screen to minimise audio output interference.
; ix = this
Application_EnterBlackout:
	push ix
	call Application_GetCLI
	ld a,(ix + CLI.blackout)
	pop ix
	and a
	ret z
	ld a,00H
	call VDP_SetColor
	jp VDP_EnableBlank

; ix = this
Application_ExitBlackout:
	ld a,(VDP_MIRROR_0 + 7)
	call VDP_SetColor
	jp VDP_DisableBlank

; Check if the stack is well above the heap
Application_CheckStack:
	ld hl,-(HEAP + HEAP_SIZE + STACK_SIZE)
	add hl,sp
	ld hl,Application_insufficientTPAError
	call nc,System_ThrowExceptionWithMessage
	ret

; Check if the heap capacity matches the free space
Application_CheckMemoryLeak:
	ld ix,Heap_main
	call Heap_GetFreeSpace
	ld hl,HEAP_SIZE
	and a
	sbc hl,bc
	call nz,System_ThrowException
	ret

;
	SECTION RAM

Application_instance: Application

	ENDS

Application_welcome:
	db "VGMPlay 1.4 by Grauw",13,10,10,0

Application_loadingFile:
	db "Loading ",0

Application_dotDotDot:
	db "...",13,10,0

Application_loadingSamples:
	db 13,10,"Loading samples...",13,10,0

Application_playing:
	db 13,10,"Playing...",13,10,0

Application_insufficientTPAError:
	db "Insufficient TPA space.",13,10,0

Application_usageInstructions:
	db "Usage: vgmplay [options] <file.vgm>",13,10
	db 13,10
	db "Options:",13,10
	db "  /l  Number of playback loops. Default: 2.",13,10
	db "  /b  Enter blackout mode during playback.",13,10,0
