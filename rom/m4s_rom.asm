; SPDX-License-Identifier: GPL-2.0-or-later
; CPC MiSTer Mass Storage experiment - Stage 1 ROM.
;
; This is a deliberately small Amstrad CPC background expansion ROM.  It
; registers one RSX command with the CPC firmware:
;
;     |HELLO
;
; Running the command prints:
;
;     M4S ROM OK
;
; No storage, MiSTer mailbox, HPS, or FPGA communication is used in Stage 1.

        include "m4s_protocol.inc"       ; Kept for future stages; unused here.

KL_ROM_BASE     equ &C000
TXT_OUTPUT      equ &BB5A                ; Firmware: print character in A.

        org KL_ROM_BASE

; ---------------------------------------------------------------------------
; CPC expansion ROM prefix.
;
; The CPC maps expansion ROMs at &C000-&FFFF.  The firmware checks the first
; byte to decide what kind of ROM this is, then uses the external command table
; pointer and jumpblock to initialise background ROMs and find RSX commands.
;
; Byte 0: ROM type.  1 means background ROM.
; Byte 1: ROM mark number.  Project-specific; 0 is fine for this experiment.
; Byte 2: version number.  Stage 1 uses version 1.
; Byte 3: modification level.  0 for the first Stage 1 build.
; Byte 4-5: address of the command name table.
; Byte 6 onward: three-byte JP entries, one per command name.
; ---------------------------------------------------------------------------
rom_prefix:
        db 1                             ; Background ROM.
        db 0                             ; Mark number.
        db 1                             ; Version.
        db 0                             ; Modification level.
        dw command_names                 ; External command name table.

        jp rom_init                      ; Entry 0: firmware power-up entry.
        jp rsx_hello                     ; Entry 1: BASIC command |HELLO.

; ---------------------------------------------------------------------------
; External command names.
;
; Each name corresponds to the same-numbered JP entry above.  The last
; character of each name has bit 7 set, and the whole table ends with zero.
;
; Entry 0 is the background ROM initialisation routine.  It needs a name in the
; table, but it is not meant to be called from BASIC.  Including a space keeps
; normal BASIC syntax from generating this command.
; ---------------------------------------------------------------------------
command_names:
        db "M4S BOO", &D4                ; Entry 0: rom_init ("T" + bit 7).
        db "HELL", &CF                   ; Entry 1: rsx_hello ("O" + bit 7).
        db 0                             ; End of command table.

; ---------------------------------------------------------------------------
; Background ROM initialisation.
;
; Entry conditions from the firmware:
;   DE = lowest byte in the free memory pool
;   HL = highest byte in the free memory pool
;
; This ROM does not need workspace RAM yet, so it preserves DE and HL.  It does
; print a short sign-on line so the user can see that the ROM was found during
; boot.  It then returns carry set to tell the firmware that initialisation
; succeeded.  The firmware will then register this ROM as an external command
; provider.
; ---------------------------------------------------------------------------
rom_init:
        push de
        push hl
        ld hl, msg_intro
        call print_string
        pop hl
        pop de
        scf
        ret

; ---------------------------------------------------------------------------
; |HELLO RSX implementation.
;
; BASIC enters external commands with:
;   A  = parameter count
;   IX = parameter block
;   IY = ROM upper workspace address for background ROM commands
;
; |HELLO takes no parameters, so all of those registers can be ignored.  External
; command routines may corrupt AF, BC, DE, HL, IX and IY on exit.
; ---------------------------------------------------------------------------
rsx_hello:
        ld hl, msg_hello
        call print_string
        ret

; Print a zero-terminated string at HL through the CPC firmware.
print_string:
        ld a, (hl)
        or a
        ret z
        call TXT_OUTPUT
        inc hl
        jr print_string

msg_hello:
        db "M4S ROM OK", 13, 10, 0

msg_intro:
        db " M4S ROM Stage 1 installed", 13, 10, 13, 10, 0

; Expansion ROM images are 16KB.  Pad unused space with &FF, the normal erased
; EPROM byte value.  The build script assembles this as a raw binary suitable
; for MiSTer's .eXX expansion ROM loader.
        ds &4000 - ($ - KL_ROM_BASE), &FF
