; SPDX-License-Identifier: GPL-2.0-or-later
; CPC MiSTer Mass Storage experiment ROM.
;
; This is a deliberately small Amstrad CPC background expansion ROM.  It
; registers RSX commands with the CPC firmware:
;
;     |HELLO
;     |M4DIR
;     |M4CD
;     |M4CD,"DIR"
;     |M4TYPE,"FILE.TXT"
;     |M4DUMP,"FILE.BIN"
;     |M4INFO,"FILE.BIN"
;     |M4LOAD,"FILE.BIN"
;     |M4LOAD,"FILE.BIN",&8000
;     |M4LOADH,"FILE.BIN"
;
; Running |HELLO prints:
;
;     M4S ROM OK
;
; Running |M4DIR reads a directory text stream from the experimental FPGA
; mailbox ports.

        include "m4s_protocol.inc"       ; Mailbox port and command constants.

KL_ROM_BASE     equ &C000
KM_WAIT_CHAR    equ &BB06                ; Firmware: wait for a keypress.
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
        jp rsx_m4info                    ; Entry 6: BASIC command |M4INFO.
        jp rsx_m4loadh                   ; Entry 7: BASIC command |M4LOADH.
        jp rsx_m4cd                      ; Entry 8: BASIC command |M4CD.

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
        db "M4INF", &CF                  ; Entry 6: rsx_m4info ("O" + bit 7).
        db "M4LOAD", &C8                 ; Entry 7: rsx_m4loadh ("H" + bit 7).
        db "M4C", &C4                    ; Entry 8: rsx_m4cd ("D" + bit 7).
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
; |M4CD and |M4CD,"dirname" RSX implementation.
;
; With no parameter, resets Main_MiSTer's current shared-folder view to the
; shared root.  With one string parameter, enters a child directory under the
; current folder.  Main_MiSTer rejects absolute paths and parent traversal.
; ---------------------------------------------------------------------------
rsx_m4cd:
        cp 0
        jr z, rsx_m4cd_root
        cp 1
        jr z, rsx_m4cd_have_param
        ld hl, msg_cd_usage
        call print_string
        ret

rsx_m4cd_root:
        ld a, M4S_CMD_REQ_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a

        ld bc, M4S_PORT_DATA
        ld a, "C"
        out (c), a
        ld a, ":"
        out (c), a
        xor a
        out (c), a
        jr rsx_m4cd_send_command

rsx_m4cd_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4cd_nonempty
        jr rsx_m4cd_root

rsx_m4cd_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, M4S_CMD_REQ_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a

        ld bc, M4S_PORT_DATA
        ld a, "C"
        out (c), a
        ld a, ":"
        out (c), a

rsx_m4cd_send_name:
        ld a, (de)
        push bc
        ld bc, M4S_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_m4cd_send_name

        xor a
        ld bc, M4S_PORT_DATA
        out (c), a

rsx_m4cd_send_command:
        ld a, M4S_CMD_TYPE
        ld bc, M4S_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_m4cd_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_m4cd_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_m4cd_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_m4cd_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_m4cd_loop

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
; |M4INFO,"filename" RSX implementation.
;
; Requests host-side metadata for a shared file.  Main_MiSTer currently reports
; file size and AMSDOS header fields if the first 128 bytes pass the AMSDOS
; checksum.
; ---------------------------------------------------------------------------
rsx_m4info:
        cp 1
        jr z, rsx_m4info_have_param
        ld hl, msg_info_usage
        call print_string
        ret

rsx_m4info_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4info_nonempty
        ld hl, msg_info_usage
        call print_string
        ret

rsx_m4info_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, M4S_CMD_REQ_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a

        ld bc, M4S_PORT_DATA
        ld a, "I"
        out (c), a
        ld a, ":"
        out (c), a

rsx_m4info_send_name:
        ld a, (de)
        push bc
        ld bc, M4S_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_m4info_send_name

        xor a
        ld bc, M4S_PORT_DATA
        out (c), a

        ld a, M4S_CMD_TYPE
        ld bc, M4S_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_m4info_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_m4info_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_m4info_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_m4info_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_m4info_loop

; ---------------------------------------------------------------------------
; |M4LOAD,"filename" RSX implementation.
;
; Stage 4 proof of raw binary transfer.  This loads a file from the shared
; folder into CPC RAM at &4000 in 512-byte chunks.  Each chunk response starts
; with a little-endian 16-bit byte count followed by raw file data.
; ---------------------------------------------------------------------------
rsx_m4load:
        cp 1
        jr z, rsx_m4load_one_param
        cp 2
        jr z, rsx_m4load_two_params
        ld hl, msg_load_usage
        call print_string
        ret

rsx_m4load_one_param:
        ld iy, 0                         ; Filename descriptor is at IX+0.
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4load_nonempty
        ld hl, msg_load_usage
        call print_string
        ret

rsx_m4load_two_params:
        ld iy, 1                         ; Filename descriptor is at IX+2.
        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4load_nonempty
        ld hl, msg_load_usage
        call print_string
        ret

rsx_m4load_nonempty:
        push iy
        pop bc
        ld a, b
        or c
        jr z, rsx_m4load_default_addr
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = destination pointer.
        ld a, h
        cp &40
        jr c, rsx_m4load_error
        jr rsx_m4load_addr_ready

rsx_m4load_default_addr:
        ld hl, M4S_LOAD_ADDR             ; HL = default destination pointer.

rsx_m4load_addr_ready:
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

; ---------------------------------------------------------------------------
; |M4LOADH,"filename" RSX implementation.
;
; Reads AMSDOS metadata, prompts the user, loads the payload at the AMSDOS load
; address, and jumps to the AMSDOS entry address.  This is deliberately separate
; from M4LOAD because it may write to low memory.
; ---------------------------------------------------------------------------
rsx_m4loadh:
        cp 1
        jr z, rsx_m4loadh_have_param
        ld hl, msg_loadh_usage
        call print_string
        ret

rsx_m4loadh_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_m4loadh_nonempty
        ld hl, msg_loadh_usage
        call print_string
        ret

rsx_m4loadh_nonempty:
        push ix
        call rsx_m4info_have_param
        ld hl, msg_loadh_prompt
        call print_string
        call KM_WAIT_CHAR
        cp "Y"
        jr z, rsx_m4loadh_confirmed
        cp "y"
        jr z, rsx_m4loadh_confirmed
        pop ix
        ld hl, msg_loadh_cancelled
        call print_string
        ret

rsx_m4loadh_confirmed:
        pop ix
        ld hl, 0                         ; HL = destination pointer, filled
                                         ; from the first response header.
        ld de, 0                         ; DE = file offset for next chunk.
        ld iy, 0                         ; IY = entry address.

rsx_m4loadh_chunk:
        call m4loadh_send_request

        ld a, M4S_CMD_TYPE
        ld bc, M4S_PORT_COMMAND
        out (c), a

        call m4load_read_byte
        jr nc, rsx_m4load_error
        ld c, a
        call m4load_read_byte
        jr nc, rsx_m4load_error
        ld b, a                          ; BC = returned payload byte count.

        ld a, b
        cp 3
        jr nc, rsx_m4load_error          ; Refuse counts above 512 bytes.
        cp 2
        jr nz, rsx_m4loadh_count_valid
        ld a, c
        or a
        jr nz, rsx_m4load_error

rsx_m4loadh_count_valid:
        call m4load_read_byte            ; Read AMSDOS load address low byte.
        jr nc, rsx_m4load_error
        push af
        call m4load_read_byte            ; Read AMSDOS load address high byte.
        jr nc, rsx_m4load_error
        push af
        ld a, d
        or e
        jr nz, rsx_m4loadh_drop_load_addr
        pop af
        ld h, a
        pop af
        ld l, a
        jr rsx_m4loadh_read_entry

rsx_m4loadh_drop_load_addr:
        pop af
        pop af

rsx_m4loadh_read_entry:
        push hl
        call m4load_read_byte            ; Read AMSDOS entry address low byte.
        jp nc, rsx_m4load_error
        push af
        call m4load_read_byte            ; Read AMSDOS entry address high byte.
        jp nc, rsx_m4load_error
        ld h, a
        pop af
        ld l, a
        push hl
        pop iy
        pop hl

        call m4load_read_byte            ; Read AMSDOS type byte.
        jp nc, rsx_m4load_error
        push af

        ld a, b
        or c
        jr z, rsx_m4loadh_done

        pop af
rsx_m4loadh_write_loop:
        call m4load_read_byte
        jp nc, rsx_m4load_error
        ld (hl), a
        inc hl
        inc de
        dec bc
        ld a, b
        or c
        jr nz, rsx_m4loadh_write_loop

        ld a, d
        or e
        jp z, rsx_m4load_done

        jr rsx_m4loadh_chunk

rsx_m4loadh_done:
        pop af
        cp &00                           ; BASIC: load only, then user can RUN.
        jp z, rsx_m4loadh_basic_done
        cp &01                           ; Protected BASIC: load only too.
        jp z, rsx_m4loadh_basic_done
        cp &02                           ; Binary: jump if an entry exists.
        jp nz, rsx_m4load_done
        push iy
        pop hl
        ld a, h
        or l
        jp z, rsx_m4load_done
        jp (hl)

rsx_m4loadh_basic_done:
        ld hl, msg_loadh_basic_done
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

        push iy
        pop hl
        ld a, h
        or l
        jr z, m4load_send_filename_at_ix0

        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = string descriptor.
        jr m4load_send_filename_descriptor

m4load_send_filename_at_ix0:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.

m4load_send_filename_descriptor:
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

; Send request "H:OOOO:filename", where OOOO is the payload offset in DE.
m4loadh_send_request:
        push hl
        push de

        ld a, M4S_CMD_REQ_BEGIN
        ld bc, M4S_PORT_COMMAND
        out (c), a

        ld bc, M4S_PORT_DATA
        ld a, "H"
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

m4loadh_send_name:
        ld a, (de)
        push bc
        ld bc, M4S_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz m4loadh_send_name

        xor a
        ld bc, M4S_PORT_DATA
        out (c), a

        pop de
        pop hl
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
        db " M4S ROM Stage 4.5 installed", 13, 10, 13, 10, 0

msg_cd_usage:
        db "Usage: |M4CD,", 34, "DIR", 34, 13, 10, 0

msg_type_usage:
        db "Usage: |M4TYPE,", 34, "FILE.TXT", 34, 13, 10, 0

msg_dump_usage:
        db "Usage: |M4DUMP,", 34, "FILE.BIN", 34, 13, 10, 0

msg_info_usage:
        db "Usage: |M4INFO,", 34, "FILE.BIN", 34, 13, 10, 0

msg_load_usage:
        db "Usage: |M4LOAD,", 34, "FILE.BIN", 34, ",&8000", 13, 10, 0

msg_load_done:
        db "Loaded", 13, 10, 0

msg_load_error:
        db "Load failed", 13, 10, 0

msg_loadh_usage:
        db "Usage: |M4LOADH,", 34, "FILE.BIN", 34, 13, 10, 0

msg_loadh_prompt:
        db "Load and CALL entry? Y/N ", 0

msg_loadh_cancelled:
        db 13, 10, "Cancelled", 13, 10, 0

msg_loadh_basic_done:
        db 13, 10, "Loaded BASIC - type RUN", 13, 10, 0

; Expansion ROM images are 16KB.  Pad unused space with &FF, the normal erased
; EPROM byte value.  The build script assembles this as a raw binary suitable
; for MiSTer's .eXX expansion ROM loader.
        ds &4000 - ($ - KL_ROM_BASE), &FF
