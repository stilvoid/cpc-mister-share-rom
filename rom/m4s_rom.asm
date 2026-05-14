; SPDX-License-Identifier: GPL-2.0-or-later
; CPC MiSTer Mass Storage experiment ROM.
;
; This is a deliberately small Amstrad CPC background expansion ROM.  It
; registers RSX commands with the CPC firmware:
;
;     |HELLO
;     |M4DIR
;     |M4TYPE,"FILE.TXT"
;     |M4DUMP,"FILE.BIN"
;     |M4LOAD,"FILE.BIN"
;
; Running |HELLO prints:
;
;     M4S ROM OK
;
; Running |M4DIR reads a directory text stream from the experimental FPGA
; mailbox ports.

        include "m4s_protocol.inc"       ; Mailbox port and command constants.

KL_ROM_BASE     equ &C000
TXT_OUTPUT      equ &BB5A                ; Firmware: print character in A.
CHAR_CR         equ 13
CHAR_LF         equ 10
M4S_LOAD_ADDR   equ &4000

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
        jp rsx_m4dir                     ; Entry 2: BASIC command |M4DIR.
        jp rsx_m4type                    ; Entry 3: BASIC command |M4TYPE.
        jp rsx_m4dump                    ; Entry 4: BASIC command |M4DUMP.
        jp rsx_m4load                    ; Entry 5: BASIC command |M4LOAD.

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
        db "M4DI", &D2                   ; Entry 2: rsx_m4dir ("R" + bit 7).
        db "M4TYP", &C5                  ; Entry 3: rsx_m4type ("E" + bit 7).
        db "M4DUM", &D0                  ; Entry 4: rsx_m4dump ("P" + bit 7).
        db "M4LOA", &C4                  ; Entry 5: rsx_m4load ("D" + bit 7).
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

; ---------------------------------------------------------------------------
; |M4DIR RSX implementation.
;
; Stage 2 proves the Z80-to-FPGA mailbox by issuing DIR_BEGIN and printing the
; returned zero-terminated byte stream.  The FPGA currently supplies hardcoded
; mock data.
; ---------------------------------------------------------------------------
rsx_m4dir:
        ld a, M4S_CMD_DIR_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a
        xor a
        ld e, a

rsx_m4dir_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_m4dir_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_m4dir_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_m4dir_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_m4dir_loop

; ---------------------------------------------------------------------------
; |M4TYPE,"filename" RSX implementation.
;
; This is a small Stage 4 proof of concept.  It sends a single filename string
; to the FPGA mailbox, asks Main_MiSTer to read it from the shared folder, and
; prints the returned byte stream.
; ---------------------------------------------------------------------------
rsx_m4type:
        cp 1
        jr z, rsx_m4type_have_param
        ld hl, msg_type_usage
        call print_string
        ret

rsx_m4type_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4type_nonempty
        ld hl, msg_type_usage
        call print_string
        ret

rsx_m4type_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, M4S_CMD_REQ_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a

rsx_m4type_send_name:
        ld a, (de)
        push bc
        ld bc, M4S_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_m4type_send_name

        xor a
        ld bc, M4S_PORT_DATA
        out (c), a

        ld a, M4S_CMD_TYPE
        ld bc, M4S_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_m4type_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_m4type_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_m4type_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_m4type_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_m4type_loop

; ---------------------------------------------------------------------------
; |M4DUMP,"filename" RSX implementation.
;
; The current mailbox stream is zero-terminated, so it cannot carry arbitrary
; binary bytes directly.  M4DUMP asks Main_MiSTer to read the file and return an
; ASCII hex dump, proving the host-side binary read path without changing the
; stream framing yet.
; ---------------------------------------------------------------------------
rsx_m4dump:
        cp 1
        jr z, rsx_m4dump_have_param
        ld hl, msg_dump_usage
        call print_string
        ret

rsx_m4dump_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4dump_nonempty
        ld hl, msg_dump_usage
        call print_string
        ret

rsx_m4dump_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, M4S_CMD_REQ_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a

        ld bc, M4S_PORT_DATA
        ld a, "D"
        out (c), a
        ld a, ":"
        out (c), a

rsx_m4dump_send_name:
        ld a, (de)
        push bc
        ld bc, M4S_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_m4dump_send_name

        xor a
        ld bc, M4S_PORT_DATA
        out (c), a

        ld a, M4S_CMD_TYPE
        ld bc, M4S_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_m4dump_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_m4dump_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_m4dump_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_m4dump_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_m4dump_loop

; ---------------------------------------------------------------------------
; |M4LOAD,"filename" RSX implementation.
;
; Stage 4 proof of raw binary transfer.  This loads a file from the shared
; folder into CPC RAM at &4000 in 512-byte chunks.  Each chunk response starts
; with a little-endian 16-bit byte count followed by raw file data.
; ---------------------------------------------------------------------------
rsx_m4load:
        cp 1
        jr z, rsx_m4load_have_param
        ld hl, msg_load_usage
        call print_string
        ret

rsx_m4load_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4load_nonempty
        ld hl, msg_load_usage
        call print_string
        ret

rsx_m4load_nonempty:
        ld hl, M4S_LOAD_ADDR             ; HL = destination pointer.
        ld de, 0                         ; DE = file offset for next chunk.

rsx_m4load_chunk:
        call m4load_send_request

        ld a, M4S_CMD_TYPE
        ld bc, M4S_PORT_COMMAND
        out (c), a

        call m4load_read_byte
        jr nc, rsx_m4load_error
        ld c, a
        call m4load_read_byte
        jr nc, rsx_m4load_error
        ld b, a                          ; BC = returned byte count.

        ld a, b
        cp 3
        jr nc, rsx_m4load_error          ; Refuse counts above 512 bytes.
        cp 2
        jr nz, rsx_m4load_count_valid
        ld a, c
        or a
        jr nz, rsx_m4load_error

rsx_m4load_count_valid:
        ld a, b
        or c
        jr z, rsx_m4load_done

rsx_m4load_write_loop:
        call m4load_read_byte
        jr nc, rsx_m4load_error
        ld (hl), a
        inc hl
        inc de
        dec bc
        ld a, b
        or c
        jr nz, rsx_m4load_write_loop

        ld a, d                          ; Stop if the 16-bit proof offset
        or e                             ; wraps around at 64KB.
        jr z, rsx_m4load_done

        jr rsx_m4load_chunk

rsx_m4load_done:
        ld hl, msg_load_done
        call print_string
        ret

rsx_m4load_error:
        ld hl, msg_load_error
        call print_string
        ret

; Read one mailbox byte while preserving the active chunk state in HL/BC/DE.
m4load_read_byte:
        push hl
        push bc
        push de
        call mailbox_read_byte
        pop de
        pop bc
        pop hl
        ret

; Send request "L:OOOO:filename", where OOOO is the 16-bit file offset in DE.
m4load_send_request:
        push hl
        push de

        ld a, M4S_CMD_REQ_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a

        ld bc, M4S_PORT_DATA
        ld a, "L"
        out (c), a
        ld a, ":"
        out (c), a
        ld a, d
        call m4load_send_hex_byte
        ld a, e
        call m4load_send_hex_byte
        ld a, ":"
        ld bc, M4S_PORT_DATA
        out (c), a

        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld b, (hl)                       ; B = filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = filename data.

m4load_send_name:
        ld a, (de)
        push bc
        ld bc, M4S_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz m4load_send_name

        xor a
        ld bc, M4S_PORT_DATA
        out (c), a

        pop de
        pop hl
        ret

m4load_send_hex_byte:
        push af
        rrca
        rrca
        rrca
        rrca
        call m4load_send_hex_nibble
        pop af

m4load_send_hex_nibble:
        and &0F
        add a, "0"
        cp "9" + 1
        jr c, m4load_send_hex_digit
        add a, 7

m4load_send_hex_digit:
        ld bc, M4S_PORT_DATA
        out (c), a
        ret

; Wait for one byte from the mailbox.
;
; Carry set:   A contains a byte read from DATA.
; Carry clear: no byte is available, the stream ended, or the mailbox signalled
;              error/timeout.
mailbox_read_byte:
        ld de, 0

mailbox_wait:
        ld bc, M4S_PORT_STATUS
        in a, (c)
        bit 3, a                         ; ERROR.
        jr nz, mailbox_no_byte
        bit 0, a                         ; DATA_READY.
        jr nz, mailbox_get_byte
        bit 4, a                         ; END_OF_STREAM.
        jr nz, mailbox_no_byte

        dec de
        ld a, d
        or e
        jr nz, mailbox_wait

mailbox_no_byte:
        xor a
        ret

mailbox_get_byte:
        ld bc, M4S_PORT_DATA
        in a, (c)
        scf
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
        db " M4S ROM Stage 4.2 installed", 13, 10, 13, 10, 0

msg_type_usage:
        db "Usage: |M4TYPE,", 34, "FILE.TXT", 34, 13, 10, 0

msg_dump_usage:
        db "Usage: |M4DUMP,", 34, "FILE.BIN", 34, 13, 10, 0

msg_load_usage:
        db "Usage: |M4LOAD,", 34, "FILE.BIN", 34, 13, 10, 0

msg_load_done:
        db "Loaded at &4000", 13, 10, 0

msg_load_error:
        db "Load failed", 13, 10, 0

; Expansion ROM images are 16KB.  Pad unused space with &FF, the normal erased
; EPROM byte value.  The build script assembles this as a raw binary suitable
; for MiSTer's .eXX expansion ROM loader.
        ds &4000 - ($ - KL_ROM_BASE), &FF
