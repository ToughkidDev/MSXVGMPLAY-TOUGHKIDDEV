;
; DOS2 runtime
;
DOS2Runtime: MACRO ?main
	Entry:
		call DOS_IsDOS2
		ld hl,DOS2Runtime_dos2Required
		jp c,System_PrintLn

		ld de,DOS2Runtime_Abort
		call DOS_DefineAbortExitRoutine

		ld hl,?main
		call System_TryCall

		call System_HasException
		jr nz,Exception

		ld de,0
		call DOS_DefineAbortExitRoutine
		ret

	Exception:
		; _TERM itself invokes the abort exit routine while it is installed.
		; Unregister it before propagating an uncaught exception to DOS, or the
		; abort handler unwinds back here and repeatedly terminates forever.
		ld de,0
		call DOS_DefineAbortExitRoutine
		ld a,(System_instance.exceptionCode)
		cp 40H
		ld hl,(System_instance.exceptionMessage)
		call c,System_PrintLn
		; A COM program can return directly to its command processor.  Do not
		; invoke DOS _TERM for an internal exception: some DOS2-compatible
		; handlers report _TERM itself as NDOS (F6), which used to re-enter the
		; abort path and print "MSX-DOS 2 is required" forever.
		ret
	ENDM

; a = error code
; b = secondary error code
DOS2Runtime_Abort:
	cp 1
	adc a,0  ; make sure it’s never zero
	ld (System_instance.exceptionCode),a
	jp System_Unwind

;
DOS2Runtime_dos2Required:
	db "MSX-DOS 2 is required.",13,10,0
