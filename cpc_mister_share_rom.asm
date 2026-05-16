; SPDX-License-Identifier: GPL-2.0-or-later
; CPC MiSTer Share experiment ROM.
;
; This is a deliberately small Amstrad CPC background expansion ROM.  It
; registers RSX commands with the CPC firmware:
;
;     |about
;     |cd
;     |cd,"DIR"
;     |cp,"SRC","DST"
;     |debug
;     |debug,0
;     |debug,1
;     |diskread,"DISCFILE"
;     |diskread,"DISCFILE","shared/path"
;     |diskread,"DISCFILE","shared/path",0
;     |diskwrite,"shared/path"
;     |diskwrite,"shared/path","DISCFILE"
;     |exec,"FILE.BIN"
;     |hexdump,"FILE.BIN"
;     |loadm,"FILE.BIN",&8000
;     |ls
;     |ls,"DIR"
;     |mkdir,"DIR"
;     |mv,"OLD","NEW"
;     |pwd
;     |rm,"FILE"
;     |savem,"FILE.BIN",&4000,&0100
;     |stat,"FILE.BIN"
;     |type,"FILE.TXT"
;
; Commands use a small mailbox exposed by the matching Amstrad MiSTer core.

        include "cpc_mister_share_protocol.inc"       ; Mailbox port and command constants.

KL_ROM_BASE     equ &C000
KM_WAIT_CHAR    equ &BB06                ; Firmware: wait for a keypress.
TXT_OUTPUT      equ &BB5A                ; Firmware: print character in A.
CAS_IN_OPEN     equ &BC77                ; Firmware: open AMSDOS input file.
CAS_IN_CLOSE    equ &BC7A                ; Firmware: close AMSDOS input file.
CAS_IN_CHAR     equ &BC80                ; Firmware: read byte from AMSDOS input.
CAS_IN_DIRECT   equ &BC83                ; Firmware: read file directly to RAM.
CAS_OUT_OPEN    equ &BC8C                ; Firmware: open AMSDOS output file.
CAS_OUT_CLOSE   equ &BC8F                ; Firmware: close AMSDOS output file.
CAS_OUT_CHAR    equ &BC95                ; Firmware: write byte to AMSDOS output.
CHAR_CR         equ 13
CHAR_LF         equ 10
CHAR_BS         equ 8
CHAR_EOF        equ 26
CMS_LOAD_ADDR   equ &4000
CMS_DISC_BUFFER equ &8800                ; 2KB AMSDOS input buffer.
CMS_IMPORT_HEADER equ &9000              ; 128-byte saved AMSDOS header.
CMS_IMPORT_REMAIN equ &9800              ; 16-bit remaining diskread bytes.
CMS_IMPORT_FILEHEAD equ &9802            ; 16-bit AMSDOS buffer control ptr.
CMS_IMPORT_BLOCK equ &9804               ; 16-bit bytes left in AMSDOS buffer.
CMS_IMPORT_CHUNK equ &9806               ; 8-bit current shared write length.
CMS_IMPORT_REQ_TYPE equ &9807            ; "S" create/truncate or "W" patch.
CMS_IMPORT_DONE equ &9808                ; 16-bit diskread payload bytes sent.
CMS_IMPORT_SRC_DESC equ &980A            ; 16-bit diskread source descriptor.
CMS_IMPORT_DST_DESC equ &980C            ; 16-bit diskread destination descriptor.
CMS_IMPORT_HEADER_MODE equ &980E         ; Non-zero means prepend AMSDOS header.
CMS_DISKWRITE_BYTE equ &9810             ; Byte currently being written to disk.
CMS_DISKWRITE_STATUS equ &9811           ; Non-zero means CAS_OUT_CHAR failed.
CMS_DISKWRITE_HEADER equ &9812           ; 16-bit AMSDOS output header pointer.
CMS_DISKWRITE_TYPE equ &9814             ; AMSDOS output file type.
CMS_DISKWRITE_LOAD equ &9815             ; 16-bit AMSDOS output load address.
CMS_DISKWRITE_ENTRY equ &9817            ; 16-bit AMSDOS output entry address.
CMS_DISKWRITE_LOGICAL equ &9819          ; 16-bit AMSDOS output logical length.
CMS_DISKWRITE_COUNT equ &981B            ; 16-bit current host payload count.
CMS_DEBUG_MODE equ &981D                 ; Non-zero enables noisy diagnostics.
CMS_PROGRESS_SEEN equ &981E              ; Non-zero after progress output.
CMS_DISKWRITE_PROGRESS equ &981F         ; 512-byte chunks until next dot.
CMS_PROGRESS_TOTAL equ &9820             ; Total 2KB progress blocks.
CMS_PROGRESS_DONE equ &9821              ; Completed 2KB progress blocks.

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
; Byte 2: version number.
; Byte 3: modification level.
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
        jp rsx_ls                     ; Entry 1: BASIC command |ls.
        jp rsx_cd                      ; Entry 2: BASIC command |cd.
        jp rsx_pwd                       ; Entry 3: BASIC command |pwd.
        jp rsx_type                    ; Entry 4: BASIC command |type.
        jp rsx_hexdump                    ; Entry 5: BASIC command |hexdump.
        jp rsx_stat                    ; Entry 6: BASIC command |stat.
        jp rsx_loadm                    ; Entry 7: BASIC command |loadm.
        jp rsx_savem                    ; Entry 8: BASIC command |savem.
        jp rsx_exec                   ; Entry 9: BASIC command |exec.
        jp rsx_mkdir                     ; Entry 10: BASIC command |mkdir.
        jp rsx_mv                        ; Entry 11: BASIC command |mv.
        jp rsx_cp                        ; Entry 12: BASIC command |cp.
        jp rsx_rm                        ; Entry 13: BASIC command |rm.
        jp rsx_diskread                  ; Entry 14: BASIC command |diskread.
        jp rsx_diskwrite                 ; Entry 15: BASIC command |diskwrite.
        jp rsx_about                     ; Entry 16: BASIC command |about.
        jp rsx_debug                     ; Entry 17: BASIC command |debug.

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
        db "CMS BOO", &D4                ; Entry 0: rom_init ("T" + bit 7).
        db "L", &D3                      ; Entry 1: rsx_ls ("S" + bit 7).
        db "C", &C4                      ; Entry 2: rsx_cd ("D" + bit 7).
        db "PW", &C4                     ; Entry 3: rsx_pwd ("D" + bit 7).
        db "TYP", &C5                    ; Entry 4: rsx_type ("E" + bit 7).
        db "HEXDUM", &D0                 ; Entry 5: rsx_hexdump ("P" + bit 7).
        db "STA", &D4                    ; Entry 6: rsx_stat ("T" + bit 7).
        db "LOAD", &CD                   ; Entry 7: rsx_loadm ("M" + bit 7).
        db "SAVE", &CD                   ; Entry 8: rsx_savem ("M" + bit 7).
        db "EXE", &C3                    ; Entry 9: rsx_exec ("C" + bit 7).
        db "MKDI", &D2                   ; Entry 10: rsx_mkdir ("R" + bit 7).
        db "M", &D6                      ; Entry 11: rsx_mv ("V" + bit 7).
        db "C", &D0                      ; Entry 12: rsx_cp ("P" + bit 7).
        db "R", &CD                      ; Entry 13: rsx_rm ("M" + bit 7).
        db "DISKREA", &C4                ; Entry 14: rsx_diskread ("D" + bit 7).
        db "DISKWRIT", &C5               ; Entry 15: rsx_diskwrite ("E" + bit 7).
        db "ABOU", &D4                   ; Entry 16: rsx_about ("T" + bit 7).
        db "DEBU", &C7                   ; Entry 17: rsx_debug ("G" + bit 7).
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
        xor a
        ld (CMS_DEBUG_MODE), a
        ld (CMS_PROGRESS_SEEN), a
        ld hl, msg_intro
        call print_string
        pop hl
        pop de
        scf
        ret

; ---------------------------------------------------------------------------
; |about and |debug RSX implementations.
; ---------------------------------------------------------------------------
rsx_about:
        ld hl, msg_about
        call print_string
        ret

rsx_debug:
        cp 0
        jr z, rsx_debug_show
        cp 1
        jr z, rsx_debug_set
        ld hl, msg_debug_usage
        call print_string
        ret

rsx_debug_set:
        ld a, (ix+0)
        ld h, (ix+1)
        or h
        ld (CMS_DEBUG_MODE), a

rsx_debug_show:
        ld a, (CMS_DEBUG_MODE)
        or a
        jr z, rsx_debug_off
        ld hl, msg_debug_on
        call print_string
        ret

rsx_debug_off:
        ld hl, msg_debug_off
        call print_string
        ret

; ---------------------------------------------------------------------------
; |ls RSX implementation.
;
; Asks Main_MiSTer for a live shared-folder listing and prints the returned
; zero-terminated byte stream.
; ---------------------------------------------------------------------------
rsx_ls:
        cp 0
        jr z, rsx_ls_current
        cp 1
        jr z, rsx_ls_have_param
        ld hl, msg_ls_usage
        call print_string
        ret

rsx_ls_current:
        ld a, CMS_CMD_DIR_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a
        xor a
        ld e, a
        jr rsx_ls_loop

rsx_ls_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr z, rsx_ls_current

        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "G"
        out (c), a
        ld a, ":"
        out (c), a

rsx_ls_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_ls_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_ls_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_ls_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_ls_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_ls_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_ls_loop

; ---------------------------------------------------------------------------
; |cd and |cd,"dirname" RSX implementation.
;
; With no parameter, resets Main_MiSTer's current shared-folder view to the
; shared root.  With one string parameter, enters a child directory under the
; current folder.  Main_MiSTer rejects absolute paths and parent traversal.
; ---------------------------------------------------------------------------
rsx_cd:
        cp 0
        jr z, rsx_cd_root
        cp 1
        jr z, rsx_cd_have_param
        ld hl, msg_cd_usage
        call print_string
        ret

rsx_cd_root:
        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "C"
        out (c), a
        ld a, ":"
        out (c), a
        xor a
        out (c), a
        jr rsx_cd_send_command

rsx_cd_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_cd_nonempty
        jr rsx_cd_root

rsx_cd_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "C"
        out (c), a
        ld a, ":"
        out (c), a

rsx_cd_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_cd_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

rsx_cd_send_command:
        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_cd_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_cd_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_cd_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_cd_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_cd_loop

; ---------------------------------------------------------------------------
; |pwd RSX implementation.
;
; Main_MiSTer treats "C:." as a directory change to the current directory and
; returns the current path without mutating it.
; ---------------------------------------------------------------------------
rsx_pwd:
        cp 0
        jr z, rsx_pwd_no_params
        ld hl, msg_pwd_usage
        call print_string
        ret

rsx_pwd_no_params:
        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "C"
        out (c), a
        ld a, ":"
        out (c), a
        ld a, "."
        out (c), a
        xor a
        out (c), a
        jr rsx_cd_send_command

; ---------------------------------------------------------------------------
; |type,"filename" RSX implementation.
;
; Sends a single filename request to Main_MiSTer and prints the returned byte
; stream.
; ---------------------------------------------------------------------------
rsx_type:
        cp 1
        jr z, rsx_type_have_param
        ld hl, msg_type_usage
        call print_string
        ret

rsx_type_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_type_nonempty
        ld hl, msg_type_usage
        call print_string
        ret

rsx_type_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

rsx_type_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_type_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_type_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_type_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_type_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_type_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_type_loop

; ---------------------------------------------------------------------------
; |hexdump,"filename" RSX implementation.
;
; The current mailbox stream is zero-terminated, so it cannot carry arbitrary
; binary bytes directly.  The command asks Main_MiSTer to read the file and return an
; ASCII hex dump, proving the host-side binary read path without changing the
; stream framing yet.
; ---------------------------------------------------------------------------
rsx_hexdump:
        cp 1
        jr z, rsx_hexdump_have_param
        ld hl, msg_dump_usage
        call print_string
        ret

rsx_hexdump_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_hexdump_nonempty
        ld hl, msg_dump_usage
        call print_string
        ret

rsx_hexdump_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "D"
        out (c), a
        ld a, ":"
        out (c), a

rsx_hexdump_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_hexdump_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_hexdump_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_hexdump_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_hexdump_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_hexdump_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_hexdump_loop

; ---------------------------------------------------------------------------
; |stat,"filename" RSX implementation.
;
; Requests host-side metadata for a shared file.  Main_MiSTer currently reports
; file size and AMSDOS header fields if the first 128 bytes pass the AMSDOS
; checksum.
; ---------------------------------------------------------------------------
rsx_stat:
        cp 1
        jr z, rsx_stat_have_param
        ld hl, msg_info_usage
        call print_string
        ret

rsx_stat_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_stat_nonempty
        ld hl, msg_info_usage
        call print_string
        ret

rsx_stat_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "I"
        out (c), a
        ld a, ":"
        out (c), a

rsx_stat_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_stat_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_stat_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_stat_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_stat_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_stat_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_stat_loop

; ---------------------------------------------------------------------------
; |mkdir,"dirname" RSX implementation.
;
; Creates one directory in the current shared folder.  Main_MiSTer validates the
; name and refuses traversal outside the shared root.
; ---------------------------------------------------------------------------
rsx_mkdir:
        cp 1
        jr z, rsx_mkdir_have_param
        ld hl, msg_mkdir_usage
        call print_string
        ret

rsx_mkdir_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_mkdir_nonempty
        ld hl, msg_mkdir_usage
        call print_string
        ret

rsx_mkdir_nonempty:
        ld b, a                          ; B = remaining length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = string data.

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "K"
        out (c), a
        ld a, ":"
        out (c), a

rsx_mkdir_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz rsx_mkdir_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_mkdir_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_mkdir_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_mkdir_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_mkdir_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_mkdir_loop

; ---------------------------------------------------------------------------
; |mv,"old","new" RSX implementation.
;
; Renames one file or directory in the current shared folder.  Main_MiSTer
; refuses path traversal and refuses to overwrite an existing destination.
; ---------------------------------------------------------------------------
rsx_mv:
        cp 2
        jr z, rsx_mv_have_params
        ld hl, msg_mv_usage
        call print_string
        ret

rsx_mv_have_params:
        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = old name string descriptor.
        ld a, (hl)
        or a
        jr nz, rsx_mv_old_nonempty
        ld hl, msg_mv_usage
        call print_string
        ret

rsx_mv_old_nonempty:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = new name string descriptor.
        ld a, (hl)
        or a
        jr nz, rsx_mv_nonempty
        ld hl, msg_mv_usage
        call print_string
        ret

rsx_mv_nonempty:
        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "N"
        out (c), a
        ld a, ":"
        out (c), a

        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = old name string descriptor.
        call mv_send_descriptor

        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = new name string descriptor.
        call mv_send_descriptor

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_mv_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_mv_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_mv_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_mv_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_mv_loop

mv_send_descriptor:
        ld b, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)

mv_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz mv_send_name
        ret

; ---------------------------------------------------------------------------
; |cp,"src","dst" RSX implementation.
;
; Copies one file within the shared folder.  Main_MiSTer resolves relative
; source and destination paths and refuses to overwrite an existing destination.
; ---------------------------------------------------------------------------
rsx_cp:
        cp 2
        jr z, rsx_cp_have_params
        ld hl, msg_cp_usage
        call print_string
        ret

rsx_cp_have_params:
        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = source string descriptor.
        ld a, (hl)
        or a
        jr nz, rsx_cp_source_nonempty
        ld hl, msg_cp_usage
        call print_string
        ret

rsx_cp_source_nonempty:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = destination string descriptor.
        ld a, (hl)
        or a
        jr nz, rsx_cp_nonempty
        ld hl, msg_cp_usage
        call print_string
        ret

rsx_cp_nonempty:
        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "P"
        out (c), a
        ld a, ":"
        out (c), a

        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = source string descriptor.
        call mv_send_descriptor

        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = destination string descriptor.
        call mv_send_descriptor

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_cp_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_cp_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_cp_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_cp_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_cp_loop

; ---------------------------------------------------------------------------
; |rm,"file" RSX implementation.
;
; Removes one file in the current shared folder.  Main_MiSTer refuses
; directories, paths, and traversal.
; ---------------------------------------------------------------------------
rsx_rm:
        cp 1
        jr z, rsx_rm_have_param
        ld hl, msg_rm_usage
        call print_string
        ret

rsx_rm_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)
        or a
        jr nz, rsx_rm_nonempty
        ld hl, msg_rm_usage
        call print_string
        ret

rsx_rm_nonempty:
        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "R"
        out (c), a
        ld a, ":"
        out (c), a

        ld l, (ix+0)
        ld h, (ix+1)
        call mv_send_descriptor

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        xor a
        ld e, a

rsx_rm_loop:
        call mailbox_read_byte
        ret nc
        or a
        ret z
        cp CHAR_LF
        jr nz, rsx_rm_output
        ld a, e
        cp CHAR_CR
        ld a, CHAR_LF
        jr z, rsx_rm_output
        push af
        ld a, CHAR_CR
        call TXT_OUTPUT
        pop af
rsx_rm_output:
        call TXT_OUTPUT
        ld e, a
        jr rsx_rm_loop

; ---------------------------------------------------------------------------
; |diskread,"discfile"[,"shared/path"[,preserve_header]] RSX implementation.
;
; Reads a file through AMSDOS from the currently selected CPC disk and writes it
; to the current shared folder.  The host refuses an existing destination, so an
; interrupted disk read is visible rather than silently replacing a good file.
; ---------------------------------------------------------------------------
rsx_diskread:
        cp 1
        jr z, rsx_import_one_param
        cp 2
        jr z, rsx_import_two_params
        cp 3
        jr z, rsx_import_three_params
        ld hl, msg_import_usage
        call print_string
        ret

rsx_import_one_param:
        ld l, (ix+0)                     ; Disk filename is also shared path.
        ld h, (ix+1)
        ld (CMS_IMPORT_SRC_DESC), hl
        ld (CMS_IMPORT_DST_DESC), hl
        ld a, 1
        ld (CMS_IMPORT_HEADER_MODE), a
        jr rsx_import_have_params

rsx_import_two_params:
        ld l, (ix+2)                     ; First BASIC arg: disk filename.
        ld h, (ix+3)
        ld (CMS_IMPORT_SRC_DESC), hl
        ld l, (ix+0)                     ; Second BASIC arg: shared path.
        ld h, (ix+1)
        ld (CMS_IMPORT_DST_DESC), hl
        ld a, 1
        ld (CMS_IMPORT_HEADER_MODE), a
        jr rsx_import_have_params

rsx_import_three_params:
        ld l, (ix+4)                     ; First BASIC arg: disk filename.
        ld h, (ix+5)
        ld (CMS_IMPORT_SRC_DESC), hl
        ld l, (ix+2)                     ; Second BASIC arg: shared path.
        ld h, (ix+3)
        ld (CMS_IMPORT_DST_DESC), hl
        ld a, (ix+0)                     ; Third BASIC arg: 0 strips header.
        ld h, (ix+1)
        or h
        ld (CMS_IMPORT_HEADER_MODE), a

rsx_import_have_params:
        ld hl, (CMS_IMPORT_SRC_DESC)      ; HL = disk filename descriptor.
        ld a, (hl)
        or a
        jr nz, rsx_import_source_nonempty
        ld hl, msg_import_usage
        call print_string
        ret

rsx_import_source_nonempty:
        ld hl, (CMS_IMPORT_DST_DESC)      ; HL = shared destination descriptor.
        ld a, (hl)
        or a
        jr nz, rsx_import_nonempty
        ld hl, msg_import_usage
        call print_string
        ret

rsx_import_nonempty:
        xor a
        ld (CMS_PROGRESS_SEEN), a
        ld hl, (CMS_IMPORT_SRC_DESC)      ; HL = disk filename descriptor.
        ld b, (hl)                       ; B = filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl                        ; HL = disk filename data.
        ld de, CMS_DISC_BUFFER           ; DE = 2KB AMSDOS buffer.
        push ix
        call CAS_IN_OPEN
        pop ix
        jp nc, rsx_import_error

        push bc                           ; CAS_IN_OPEN returned length.
        push hl                           ; Preserve AMSDOS header pointer.
        ld de, 24                         ; AMSDOS logical length field.
        add hl, de
        ld c, (hl)
        inc hl
        ld b, (hl)                        ; BC = file payload length.
        ld (CMS_IMPORT_REMAIN), bc
        push bc
        call debug_print_lengths
        pop bc
        pop hl                            ; HL = AMSDOS header pointer.
        pop bc
        push hl
        call import_save_header
        pop hl
        ld de, -5
        add hl, de
        ld (CMS_IMPORT_FILEHEAD), hl       ; Hidden AMSDOS buffer control.

        call import_create_destination
        jp nc, rsx_import_create_error

        ld hl, msg_reading
        call print_progress_prefix
        ld hl, (CMS_IMPORT_REMAIN)
        call progress_init
        ld de, 0                          ; DE = shared destination file offset.
        push de
        push ix
        call CAS_IN_CHAR                  ; Prime AMSDOS' first 2KB buffer.
        pop ix
        pop de
        jp nc, rsx_import_close_error
        jr rsx_import_copy_buffer

rsx_import_refill:
        ld bc, (CMS_IMPORT_REMAIN)
        ld a, b
        or c
        jr z, rsx_import_close_done

        push de
        call import_prepare_next_read
        push ix
        call CAS_IN_CHAR
        pop ix
        pop de
        jr c, rsx_import_copy_buffer
        cp CHAR_EOF
        jp nz, rsx_import_close_error

rsx_import_copy_buffer:
        ld bc, (CMS_IMPORT_REMAIN)
        ld a, b
        cp 8
        jr c, rsx_import_short_block
        ld bc, 2048
        jr rsx_import_block_ready

rsx_import_short_block:
        ld bc, (CMS_IMPORT_REMAIN)

rsx_import_block_ready:
        ld (CMS_IMPORT_BLOCK), bc
        call import_load_buffer_base

rsx_import_block_loop:
        ld bc, (CMS_IMPORT_BLOCK)
        ld a, b
        or c
        jr z, rsx_import_block_done
        ld a, b
        or a
        jr nz, rsx_import_chunk_64
        ld a, c
        cp 65
        jr c, rsx_import_chunk_ready

rsx_import_chunk_64:
        ld a, 64

rsx_import_chunk_ready:
        ld (CMS_IMPORT_CHUNK), a
        call import_send_chunk_request
        jp nc, rsx_import_close_error
        ld a, (CMS_IMPORT_CHUNK)
        call import_decrease_remaining
        ld a, (CMS_IMPORT_CHUNK)
        call import_decrease_block

rsx_import_advance_chunk:
        inc hl
        inc de
        dec a
        jr nz, rsx_import_advance_chunk
        jr rsx_import_block_loop

rsx_import_block_done:
        call progress_update
        jr rsx_import_refill

rsx_import_close_done:
        ld (CMS_IMPORT_DONE), de
        push ix
        call CAS_IN_CLOSE
        pop ix
        call debug_print_done
        ld a, (CMS_IMPORT_HEADER_MODE)
        or a
        jr z, rsx_import_done
        call import_prepend_saved_header
        jp nc, rsx_import_error

rsx_import_done:
        call print_progress_newline
        ld hl, msg_import_done
        call print_string
        ret

import_save_header:
        push hl
        push de
        push bc
        push hl
        ld de, CMS_IMPORT_HEADER
        ld bc, 69
        ldir
        pop hl
        ld de, &00D4                     ; AMSDOS stores header tail separately.
        add hl, de
        ld de, CMS_IMPORT_HEADER + 69
        ld bc, 59
        ldir
        pop bc
        pop de
        pop hl
        ret

; Diagnostic for diskread length mismatches.  BC is the AMSDOS header length and
; the next word on the stack is the length returned directly by CAS_IN_OPEN.
debug_print_lengths:
        ld a, (CMS_DEBUG_MODE)
        or a
        ret z
        push hl
        push de
        push bc
        ld hl, msg_import_open_len
        call print_string
        ld hl, 12
        add hl, sp
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl
        call print_hex_word
        ld hl, msg_import_header_len
        call print_string
        pop hl
        call print_hex_word
        ld hl, msg_newline
        call print_string
        pop de
        pop hl
        ret

debug_print_done:
        ld a, (CMS_DEBUG_MODE)
        or a
        ret z
        push hl
        ld hl, msg_import_done_len
        call print_string
        ld hl, (CMS_IMPORT_DONE)
        call print_hex_word
        ld hl, msg_import_remain_len
        call print_string
        ld hl, (CMS_IMPORT_REMAIN)
        call print_hex_word
        ld hl, msg_newline
        call print_string
        pop hl
        ret

import_prepend_saved_header:
        push hl
        push de
        ld hl, CMS_IMPORT_HEADER
        call import_prepend_header_request
        jr nc, import_prepend_saved_header_failed
        pop de
        pop hl
        scf
        ret

import_prepend_saved_header_failed:
        pop de
        pop hl
        or a
        ret

import_decrease_remaining:
        push hl
        push de
        push bc
        push af
        ld e, a
        ld d, 0
        ld hl, (CMS_IMPORT_REMAIN)
        or a
        sbc hl, de
        ld (CMS_IMPORT_REMAIN), hl
        pop af
        pop bc
        pop de
        pop hl
        ret

import_decrease_block:
        push hl
        push de
        push bc
        push af
        ld e, a
        ld d, 0
        ld hl, (CMS_IMPORT_BLOCK)
        or a
        sbc hl, de
        ld (CMS_IMPORT_BLOCK), hl
        pop af
        pop bc
        pop de
        pop hl
        ret

import_load_buffer_base:
        push de
        ld hl, (CMS_IMPORT_FILEHEAD)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl
        pop de
        ret

; Prepare AMSDOS for another buffered read: point the private buffer index to
; the end of the next requested block and clear the buffered byte count, so
; CAS_IN_CHAR refills the 2KB buffer.
import_prepare_next_read:
        push hl
        push de
        push bc
        push iy
        ld hl, (CMS_IMPORT_REMAIN)
        ld a, h
        cp 8
        jr c, import_prepare_short
        ld bc, 2048
        jr import_prepare_have_size

import_prepare_short:
        ld b, h
        ld c, l

import_prepare_have_size:
        ld iy, (CMS_IMPORT_FILEHEAD)
        ld l, (iy+1)
        ld h, (iy+2)
        add hl, bc
        ld (iy+3), l
        ld (iy+4), h
        ld (iy+24), 0
        ld (iy+25), 0
        pop iy
        pop bc
        pop de
        pop hl
        ret

rsx_import_close_error:
        push ix
        call CAS_IN_CLOSE
        pop ix
        call print_progress_newline

rsx_import_error:
        ld hl, msg_import_error
        call print_string
        ret

rsx_import_create_error:
        push ix
        call CAS_IN_CLOSE
        pop ix
        ret

; ---------------------------------------------------------------------------
; |diskwrite,"shared/path"[,"discfile"] RSX implementation.
;
; Streams an AMSDOS-headered shared-folder file to the currently selected disk.
; ---------------------------------------------------------------------------
rsx_diskwrite:
        cp 1
        jr z, rsx_diskwrite_one_param
        cp 2
        jr z, rsx_diskwrite_two_params
        ld hl, msg_diskwrite_usage
        call print_string
        ret

rsx_diskwrite_one_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = shared source descriptor.
        ld (CMS_IMPORT_SRC_DESC), hl
        ld hl, 0                         ; Derive disk name from source leaf.
        ld (CMS_IMPORT_DST_DESC), hl
        jr rsx_diskwrite_have_params

rsx_diskwrite_two_params:
        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = shared source descriptor.
        ld (CMS_IMPORT_SRC_DESC), hl
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = disk destination descriptor.
        ld (CMS_IMPORT_DST_DESC), hl

rsx_diskwrite_have_params:
        ld hl, (CMS_IMPORT_SRC_DESC)
        ld a, (hl)
        or a
        jr nz, rsx_diskwrite_source_nonempty
        ld hl, msg_diskwrite_usage
        call print_string
        ret

rsx_diskwrite_source_nonempty:
        ld hl, (CMS_IMPORT_DST_DESC)
        ld a, h
        or l
        jr z, rsx_diskwrite_nonempty
        ld a, (hl)
        or a
        jr nz, rsx_diskwrite_nonempty
        ld hl, msg_diskwrite_usage
        call print_string
        ret

rsx_diskwrite_nonempty:
        xor a
        ld (CMS_PROGRESS_SEEN), a
        ld a, 4
        ld (CMS_DISKWRITE_PROGRESS), a
        ld de, 0                         ; DE = shared source file offset.
        call diskwrite_request_chunk
        jp nc, rsx_diskwrite_error

        call diskwrite_prepare_output_name
        jp nc, rsx_diskwrite_error
        ld de, CMS_DISC_BUFFER
        push ix
        call CAS_OUT_OPEN
        pop ix
        jp nc, rsx_diskwrite_error
        push hl
        ld hl, msg_writing
        call print_progress_prefix
        pop hl
        push hl
        ld hl, (CMS_DISKWRITE_LOGICAL)
        call progress_init
        pop hl
        ld (CMS_DISKWRITE_HEADER), hl
        call diskwrite_update_header
        ld de, 0                         ; DE = shared source file offset.
        ld bc, (CMS_DISKWRITE_COUNT)
        jp rsx_diskwrite_count_valid

rsx_diskwrite_chunk:
        call diskwrite_request_chunk
        jp nc, rsx_diskwrite_close_error
        jp rsx_diskwrite_count_valid

diskwrite_request_chunk:
        call cms_diskwrite_send_request

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        call cms_load_read_byte
        jp nc, diskwrite_request_failed
        ld c, a
        call cms_load_read_byte
        jp nc, diskwrite_request_failed
        ld b, a                          ; BC = returned byte count.
        ld (CMS_DISKWRITE_COUNT), bc

        call cms_load_read_byte            ; Read AMSDOS logical length low byte.
        jp nc, diskwrite_request_failed
        ld l, a
        call cms_load_read_byte            ; Read AMSDOS logical length high byte.
        jp nc, diskwrite_request_failed
        ld h, a
        ld (CMS_DISKWRITE_LOGICAL), hl

        call cms_load_read_byte            ; Read AMSDOS load address low byte.
        jp nc, diskwrite_request_failed
        ld l, a
        call cms_load_read_byte            ; Read AMSDOS load address high byte.
        jp nc, diskwrite_request_failed
        ld h, a
        ld (CMS_DISKWRITE_LOAD), hl

        call cms_load_read_byte            ; Read AMSDOS entry address low byte.
        jp nc, diskwrite_request_failed
        ld l, a
        call cms_load_read_byte            ; Read AMSDOS entry address high byte.
        jp nc, diskwrite_request_failed
        ld h, a
        ld (CMS_DISKWRITE_ENTRY), hl

        call cms_load_read_byte            ; Read AMSDOS type byte.
        jp nc, diskwrite_request_failed
        ld (CMS_DISKWRITE_TYPE), a
        ld b, 128

diskwrite_read_header_loop:
        call cms_load_read_byte
        jp nc, diskwrite_request_failed
        djnz diskwrite_read_header_loop
        ld bc, (CMS_DISKWRITE_COUNT)
        scf
        ret

diskwrite_request_failed:
        or a
        ret

rsx_diskwrite_count_valid:
        ld a, b
        cp 3
        jp nc, rsx_diskwrite_close_error ; Refuse counts above 512 bytes.
        cp 2
        jr nz, rsx_diskwrite_count_checked
        ld a, c
        or a
        jp nz, rsx_diskwrite_close_error

rsx_diskwrite_count_checked:
        ld a, b
        or c
        jp z, rsx_diskwrite_close_done

rsx_diskwrite_byte_loop:
        call cms_load_read_byte
        jp nc, rsx_diskwrite_close_error
        ld (CMS_DISKWRITE_BYTE), a

        push bc
        push de
        push ix
        ld a, (CMS_DISKWRITE_BYTE)
        call CAS_OUT_CHAR
        ld a, 0
        jr c, rsx_diskwrite_char_ok
        inc a

rsx_diskwrite_char_ok:
        ld (CMS_DISKWRITE_STATUS), a
        pop ix
        pop de
        pop bc
        ld a, (CMS_DISKWRITE_STATUS)
        or a
        jp nz, rsx_diskwrite_close_error

        inc de
        dec bc
        ld a, b
        or c
        jr nz, rsx_diskwrite_byte_loop

        ld a, d                          ; Stop if the 16-bit transfer offset
        or e                             ; wraps around at 64KB.
        jp z, rsx_diskwrite_close_done
        call diskwrite_progress_chunk
        jp rsx_diskwrite_chunk

rsx_diskwrite_close_done:
        ld (CMS_IMPORT_DONE), de
        push ix
        call CAS_OUT_CLOSE
        pop ix
        call diskwrite_progress_flush
        call print_progress_newline
        ld hl, msg_diskwrite_done
        call print_string
        ret

rsx_diskwrite_close_error:
        push ix
        call CAS_OUT_CLOSE
        pop ix
        call print_progress_newline

rsx_diskwrite_error:
        ld hl, msg_diskwrite_error
        call print_string
        ret

diskwrite_update_header:
        push hl
        push de
        push bc
        push af
        ld hl, (CMS_DISKWRITE_HEADER)
        ld de, 18
        add hl, de
        ld a, (CMS_DISKWRITE_TYPE)
        ld (hl), a
        inc hl
        xor a
        ld (hl), a                        ; Data length low.
        inc hl
        ld (hl), a                        ; Data length high.
        inc hl
        ld de, (CMS_DISKWRITE_LOAD)
        ld (hl), e
        inc hl
        ld (hl), d
        inc hl
        inc hl                            ; Logical length at header+24.
        ld de, (CMS_DISKWRITE_LOGICAL)
        ld (hl), e
        inc hl
        ld (hl), d
        inc hl
        ld bc, (CMS_DISKWRITE_ENTRY)
        ld (hl), c
        inc hl
        ld (hl), b
        ld hl, (CMS_DISKWRITE_HEADER)
        ld de, 64
        add hl, de
        xor a
        ld (hl), a                        ; Real length low, maintained by AMSDOS.
        inc hl
        ld (hl), a                        ; Real length middle.
        inc hl
        ld (hl), a                        ; Real length high.
        ld hl, (CMS_DISKWRITE_HEADER)
        ld de, 24
        add hl, de
        ld de, (CMS_DISKWRITE_LOGICAL)
        ld (hl), e                        ; Logical length low.
        inc hl
        ld (hl), d                        ; Logical length high.
        call diskwrite_update_checksum
        pop af
        pop bc
        pop de
        pop hl
        ret

diskwrite_update_checksum:
        push hl
        push de
        push bc
        ld hl, 0
        ld de, (CMS_DISKWRITE_HEADER)
        ld b, 67

diskwrite_checksum_loop:
        push bc
        ld a, (de)
        ld c, a
        ld b, 0
        add hl, bc
        inc de
        pop bc
        djnz diskwrite_checksum_loop
        ex de, hl                         ; DE = checksum, HL = header+67.
        ld hl, (CMS_DISKWRITE_HEADER)
        ld bc, 67
        add hl, bc
        ld (hl), e
        inc hl
        ld (hl), d
        pop bc
        pop de
        pop hl
        ret

import_create_destination:
        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "F"
        out (c), a
        ld a, ":"
        out (c), a

        ld hl, (CMS_IMPORT_DST_DESC)      ; HL = shared destination descriptor.
        call mv_send_descriptor

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        call cms_load_read_byte
        jp nc, import_response_failed
        cp "O"
        jp nz, import_response_failed_print
        scf
        ret

import_response_failed:
        or a
        ret

import_response_failed_print:
        call print_response_from_a
        or a
        ret

print_response_from_a:
        or a
        ret z

print_response_loop:
        call TXT_OUTPUT
        call mailbox_read_byte
        ret nc
        or a
        jr nz, print_response_loop
        ret

; Send the saved AMSDOS header to the host in two 64-byte halves.  Main_MiSTer
; prepends the complete header after the second half arrives, so the proven
; payload streaming path can remain unchanged.
import_prepend_header_request:
        push hl
        ld a, "0"
        call import_prepend_header_half
        jr nc, import_prepend_header_failed
        pop hl
        ld de, 64
        add hl, de
        ld a, "1"
        jp import_prepend_header_half

import_prepend_header_failed:
        pop hl
        or a
        ret

; Send request "Y:N:filename:HEX", where N is "0" or "1" and HL points at 64
; bytes of header data.
import_prepend_header_half:
        push hl
        push af

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "Y"
        out (c), a
        ld a, ":"
        out (c), a
        pop af
        out (c), a
        ld a, ":"
        out (c), a

        ld hl, (CMS_IMPORT_DST_DESC)      ; HL = shared destination descriptor.
        call mv_send_descriptor

        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        pop hl
        ld e, 64

import_prepend_header_data:
        ld a, (hl)
        call cms_load_send_hex_byte
        inc hl
        dec e
        jr nz, import_prepend_header_data

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        call cms_load_read_byte
        jp nc, import_response_failed
        cp "O"
        jp nz, import_response_failed
        scf
        ret

; Send request "S:OOOO:NN:filename:HEX", where OOOO is the file offset in DE,
; NN is the chunk length in A, and HL points at the chunk data.
import_send_chunk_request:
        push af
        ld a, "S"
        ld (CMS_IMPORT_REQ_TYPE), a
        pop af
        jr import_send_typed_chunk_request

; Same as import_send_chunk_request, but request type "W" patches an existing
; shared file without truncating when the offset is zero.
import_patch_chunk_request:
        push af
        ld a, "W"
        ld (CMS_IMPORT_REQ_TYPE), a
        pop af

import_send_typed_chunk_request:
        push hl
        push de
        push bc
        push af

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, (CMS_IMPORT_REQ_TYPE)
        out (c), a
        ld a, ":"
        out (c), a
        ld a, d
        call cms_load_send_hex_byte
        ld a, e
        call cms_load_send_hex_byte
        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a
        pop af
        push af
        call cms_load_send_hex_byte
        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        ld hl, (CMS_IMPORT_DST_DESC)      ; HL = shared destination descriptor.
        call mv_send_descriptor

        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        pop af
        pop bc
        pop de
        pop hl
        push hl
        push de
        push bc
        push af

        ld e, a

import_send_chunk_data:
        ld a, (hl)
        call cms_load_send_hex_byte
        inc hl
        dec e
        jr nz, import_send_chunk_data

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        pop af
        pop bc
        pop de
        pop hl

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        call cms_load_read_byte
        jp nc, import_response_failed
        cp "O"
        jp nz, import_response_failed
        scf
        ret

; ---------------------------------------------------------------------------
; |savem,"filename",&addr,&length RSX implementation.
;
; Saves a CPC memory range to a file in the current shared folder. The CPC sends
; 64-byte chunks encoded as ASCII hex so the zero-terminated mailbox request
; framing can carry arbitrary bytes.
; ---------------------------------------------------------------------------
rsx_savem:
        cp 3
        jr z, rsx_savem_have_params
        ld hl, msg_save_usage
        call print_string
        ret

rsx_savem_have_params:
        ld l, (ix+4)
        ld h, (ix+5)                     ; HL = filename string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_savem_nonempty
        ld hl, msg_save_usage
        call print_string
        ret

rsx_savem_nonempty:
        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = source memory pointer.
        ld c, (ix+0)
        ld b, (ix+1)                     ; BC = bytes left to save.
        ld a, b
        or c
        jr nz, rsx_savem_start
        ld hl, msg_save_usage
        call print_string
        ret

rsx_savem_start:
        ld de, 0                         ; DE = file offset for next chunk.

rsx_savem_chunk:
        ld a, b
        or a
        jr nz, rsx_savem_chunk_64
        ld a, c
        cp 65
        jr c, rsx_savem_chunk_ready

rsx_savem_chunk_64:
        ld a, 64

rsx_savem_chunk_ready:
        call cmsave_send_request
        push af

        push bc
        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a
        pop bc

        call cms_load_read_byte
        jr nc, rsx_savem_response_error
        cp "O"
        jr nz, rsx_savem_response_error

        pop af
rsx_savem_advance:
        inc hl
        inc de
        dec bc
        dec a
        jr nz, rsx_savem_advance

        ld a, b
        or c
        jr z, rsx_savem_done

        ld a, d                          ; Stop if the 16-bit transfer offset
        or e                             ; wraps around at 64KB.
        jr z, rsx_savem_error

        jr rsx_savem_chunk

rsx_savem_response_error:
        pop af

rsx_savem_error:
        ld hl, msg_save_error
        call print_string
        ret

rsx_savem_done:
        ld hl, msg_save_done
        call print_string
        ret

; ---------------------------------------------------------------------------
; |loadm,"filename" RSX implementation.
;
; Loads a shared-folder file into CPC RAM at &4000, or an explicit address, in
; 512-byte chunks. Each response starts with a little-endian 16-bit byte count
; followed by raw file data.
; ---------------------------------------------------------------------------
rsx_loadm:
        cp 1
        jr z, rsx_loadm_one_param
        cp 2
        jr z, rsx_loadm_two_params
        ld hl, msg_load_usage
        call print_string
        ret

rsx_loadm_one_param:
        ld iy, 0                         ; Filename descriptor is at IX+0.
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_loadm_nonempty
        ld hl, msg_load_usage
        call print_string
        ret

rsx_loadm_two_params:
        ld iy, 1                         ; Filename descriptor is at IX+2.
        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_loadm_nonempty
        ld hl, msg_load_usage
        call print_string
        ret

rsx_loadm_nonempty:
        push iy
        pop bc
        ld a, b
        or c
        jr z, rsx_loadm_default_addr
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = destination pointer.
        ld a, h
        cp &40
        jr c, rsx_loadm_error
        jr rsx_loadm_addr_ready

rsx_loadm_default_addr:
        ld hl, CMS_LOAD_ADDR             ; HL = default destination pointer.

rsx_loadm_addr_ready:
        ld de, 0                         ; DE = file offset for next chunk.

rsx_loadm_chunk:
        call cms_load_send_request

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        call cms_load_read_byte
        jp nc, rsx_loadm_error
        ld c, a
        call cms_load_read_byte
        jp nc, rsx_loadm_error
        ld b, a                          ; BC = returned byte count.

        ld a, b
        cp 3
        jr nc, rsx_loadm_error          ; Refuse counts above 512 bytes.
        cp 2
        jr nz, rsx_loadm_count_valid
        ld a, c
        or a
        jp nz, rsx_loadm_error

rsx_loadm_count_valid:
        ld a, b
        or c
        jr z, rsx_loadm_done

rsx_loadm_write_loop:
        call cms_load_read_byte
        jp nc, rsx_loadm_error
        ld (hl), a
        inc hl
        inc de
        dec bc
        ld a, b
        or c
        jr nz, rsx_loadm_write_loop

        ld a, d                          ; Stop if the 16-bit transfer offset
        or e                             ; wraps around at 64KB.
        jr z, rsx_loadm_done

        jr rsx_loadm_chunk

rsx_loadm_done:
        ld hl, msg_load_done
        call print_string
        ret

rsx_loadm_error:
        ld hl, msg_load_error
        call print_string
        ret

; ---------------------------------------------------------------------------
; |exec,"filename" RSX implementation.
;
; Reads AMSDOS metadata, loads the payload at the AMSDOS load address, and jumps
; to the AMSDOS entry address for binary files. This is deliberately separate
; from loadm because it may write to low memory.
; ---------------------------------------------------------------------------
rsx_exec:
        cp 1
        jr z, rsx_exec_have_param
        ld hl, msg_loadh_usage
        call print_string
        ret

rsx_exec_have_param:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld a, (hl)                       ; A = string length.
        or a
        jr nz, rsx_exec_nonempty
        ld hl, msg_loadh_usage
        call print_string
        ret

rsx_exec_nonempty:
        call cms_exec_check_request
        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a
        call cms_load_read_byte
        jp nc, rsx_loadm_error
        cp 1
        jp nz, rsx_loadm_error

        ld hl, 0                         ; HL = destination pointer, filled
                                         ; from the first response header.
        ld de, 0                         ; DE = file offset for next chunk.
        ld iy, 0                         ; IY = entry address.

rsx_exec_chunk:
        call cms_exech_send_request

        ld a, CMS_CMD_TYPE
        ld bc, CMS_PORT_COMMAND
        out (c), a

        call cms_load_read_byte
        jr nc, rsx_loadm_error
        ld c, a
        call cms_load_read_byte
        jr nc, rsx_loadm_error
        ld b, a                          ; BC = returned payload byte count.

        ld a, b
        cp 3
        jp nc, rsx_loadm_error          ; Refuse counts above 512 bytes.
        cp 2
        jr nz, rsx_exec_count_valid
        ld a, c
        or a
        jp nz, rsx_loadm_error

rsx_exec_count_valid:
        call cms_load_read_byte            ; Read AMSDOS load address low byte.
        jp nc, rsx_loadm_error
        push af
        call cms_load_read_byte            ; Read AMSDOS load address high byte.
        jp nc, rsx_loadm_error
        push af
        ld a, d
        or e
        jr nz, rsx_exec_drop_load_addr
        pop af
        ld h, a
        pop af
        ld l, a
        jr rsx_exec_read_entry

rsx_exec_drop_load_addr:
        pop af
        pop af

rsx_exec_read_entry:
        push hl
        call cms_load_read_byte            ; Read AMSDOS entry address low byte.
        jp nc, rsx_loadm_error
        push af
        call cms_load_read_byte            ; Read AMSDOS entry address high byte.
        jp nc, rsx_loadm_error
        ld h, a
        pop af
        ld l, a
        push hl
        pop iy
        pop hl

        call cms_load_read_byte            ; Read AMSDOS type byte.
        jp nc, rsx_loadm_error
        push af

        ld a, b
        or c
        jr z, rsx_exec_done

        pop af
rsx_exec_write_loop:
        call cms_load_read_byte
        jp nc, rsx_loadm_error
        ld (hl), a
        inc hl
        inc de
        dec bc
        ld a, b
        or c
        jr nz, rsx_exec_write_loop

        ld a, d
        or e
        jp z, rsx_loadm_done

        jr rsx_exec_chunk

rsx_exec_done:
        pop af
        cp &00                           ; BASIC: load only, then user can RUN.
        jp z, rsx_exec_basic_done
        cp &01                           ; Protected BASIC: load only too.
        jp z, rsx_exec_basic_done
        cp &02                           ; Binary: jump if an entry exists.
        jp nz, rsx_loadm_error
        push iy
        pop hl
        ld a, h
        or l
        jp z, rsx_loadm_error
        jp (hl)

rsx_exec_basic_done:
        ld hl, msg_loadh_basic_done
        call print_string
        ret

; Read one mailbox byte while preserving the active chunk state in HL/BC/DE.
cms_load_read_byte:
        push hl
        push bc
        push de
        call mailbox_read_byte
        pop de
        pop bc
        pop hl
        ret

; Send request "L:OOOO:filename", where OOOO is the 16-bit file offset in DE.
cms_load_send_request:
        push hl
        push de

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "L"
        out (c), a
        ld a, ":"
        out (c), a
        ld a, d
        call cms_load_send_hex_byte
        ld a, e
        call cms_load_send_hex_byte
        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        push iy
        pop hl
        ld a, h
        or l
        jr z, cms_load_send_filename_at_ix0

        ld l, (ix+2)
        ld h, (ix+3)                     ; HL = string descriptor.
        jr cms_load_send_filename_descriptor

cms_load_send_filename_at_ix0:
        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.

cms_load_send_filename_descriptor:
        ld b, (hl)                       ; B = filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = filename data.

cms_load_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz cms_load_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        pop de
        pop hl
        ret

cms_load_send_hex_byte:
        push af
        rrca
        rrca
        rrca
        rrca
        call cms_load_send_hex_nibble
        pop af

cms_load_send_hex_nibble:
        and &0F
        add a, "0"
        cp "9" + 1
        jr c, cms_load_send_hex_digit
        add a, 7

cms_load_send_hex_digit:
        ld bc, CMS_PORT_DATA
        out (c), a
        ret

; Send request "H:OOOO:filename", where OOOO is the payload offset in DE.
cms_exech_send_request:
        push hl
        push de

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "H"
        out (c), a
        ld a, ":"
        out (c), a
        ld a, d
        call cms_load_send_hex_byte
        ld a, e
        call cms_load_send_hex_byte
        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld b, (hl)                       ; B = filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = filename data.

cms_exech_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz cms_exech_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        pop de
        pop hl
        ret

; Send request "X:filename" to check that |exec can load the file.
cms_exec_check_request:
        push hl
        push de

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "X"
        out (c), a
        ld a, ":"
        out (c), a

        ld l, (ix+0)
        ld h, (ix+1)                     ; HL = string descriptor.
        ld b, (hl)                       ; B = filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = filename data.

cms_exec_check_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz cms_exec_check_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        pop de
        pop hl
        ret

; Send request "O:OOOO:filename" using the saved shared source descriptor.
cms_diskwrite_send_request:
        push hl
        push de

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "O"
        out (c), a
        ld a, ":"
        out (c), a
        ld a, d
        call cms_load_send_hex_byte
        ld a, e
        call cms_load_send_hex_byte
        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        ld hl, (CMS_IMPORT_SRC_DESC)      ; HL = shared source descriptor.
        ld b, (hl)                       ; B = filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = filename data.

cms_diskwrite_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz cms_diskwrite_send_name

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        pop de
        pop hl
        ret

diskwrite_prepare_output_name:
        ld hl, (CMS_IMPORT_DST_DESC)
        ld a, h
        or l
        jr z, diskwrite_source_leaf_name
        ld b, (hl)                       ; B = disk filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl                        ; HL = disk filename data.
        scf
        ret

diskwrite_source_leaf_name:
        ld hl, (CMS_IMPORT_SRC_DESC)
        ld b, (hl)                       ; B = full source path length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = source path data.
        ld h, d
        ld l, e                          ; HL = current leaf pointer.
        ld c, b                          ; C = current leaf length.

diskwrite_leaf_scan:
        ld a, b
        or a
        jr z, diskwrite_leaf_ready
        ld a, (de)
        inc de
        dec b
        cp "/"
        jr z, diskwrite_leaf_reset
        cp &5C
        jr z, diskwrite_leaf_reset
        jr diskwrite_leaf_scan

diskwrite_leaf_reset:
        ld h, d
        ld l, e
        ld c, b
        jr diskwrite_leaf_scan

diskwrite_leaf_ready:
        ld a, c
        or a
        jr z, diskwrite_leaf_failed
        ld b, c
        scf
        ret

diskwrite_leaf_failed:
        or a
        ret

; Send request "S:OOOO:NN:filename:HEX", where OOOO is the 16-bit file offset
; in DE and NN is the chunk length in A.
cmsave_send_request:
        push hl
        push de
        push bc
        push af

        ld a, CMS_CMD_REQ_BEGIN
        ld bc, CMS_PORT_COMMAND
        out (c), a

        ld bc, CMS_PORT_DATA
        ld a, "S"
        out (c), a
        ld a, ":"
        out (c), a
        ld a, d
        call cms_load_send_hex_byte
        ld a, e
        call cms_load_send_hex_byte
        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a
        pop af
        push af
        call cms_load_send_hex_byte
        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        ld l, (ix+4)
        ld h, (ix+5)                     ; HL = filename string descriptor.
        ld b, (hl)                       ; B = filename length.
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                       ; DE = filename data.

cmsave_send_name:
        ld a, (de)
        push bc
        ld bc, CMS_PORT_DATA
        out (c), a
        pop bc
        inc de
        djnz cmsave_send_name

        ld a, ":"
        ld bc, CMS_PORT_DATA
        out (c), a

        pop af
        pop bc
        pop de
        pop hl
        push hl
        push de
        push bc
        push af

        ld e, a

cmsave_send_data:
        ld a, (hl)
        call cms_load_send_hex_byte
        inc hl
        dec e
        jr nz, cmsave_send_data

        xor a
        ld bc, CMS_PORT_DATA
        out (c), a

        pop af
        pop bc
        pop de
        pop hl
        ret

; Wait for one byte from the mailbox.
;
; Carry set:   A contains a byte read from DATA.
; Carry clear: no byte is available, the stream ended, or the mailbox signalled
;              error/timeout.
mailbox_read_byte:
        ld hl, 16

mailbox_wait_outer:
        ld de, 0

mailbox_wait:
        ld bc, CMS_PORT_STATUS
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

        dec hl
        ld a, h
        or l
        jr nz, mailbox_wait_outer

mailbox_no_byte:
        xor a
        ret

mailbox_get_byte:
        ld bc, CMS_PORT_DATA
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

print_hex_word:
        ld a, h
        call print_hex_byte
        ld a, l
        call print_hex_byte
        ret

print_hex_byte:
        push af
        rrca
        rrca
        rrca
        rrca
        call print_hex_nibble
        pop af

print_hex_nibble:
        and &0F
        add a, "0"
        cp "9" + 1
        jr c, print_hex_digit
        add a, 7

print_hex_digit:
        call TXT_OUTPUT
        ret

print_progress_prefix:
        ld a, (CMS_DEBUG_MODE)
        or a
        ret nz
        ld a, 1
        ld (CMS_PROGRESS_SEEN), a
        call print_string
        ret

progress_init:
        ld a, (CMS_DEBUG_MODE)
        or a
        ret nz
        ld a, h
        srl a
        srl a
        srl a
        ld c, a                          ; C = floor(total / 2048).
        ld a, h
        and 7
        or l
        jr z, progress_init_blocks_ready
        inc c

progress_init_blocks_ready:
        ld a, c
        or a
        jr nz, progress_init_nonzero
        inc c

progress_init_nonzero:
        ld a, c
        ld (CMS_PROGRESS_TOTAL), a
        xor a
        ld (CMS_PROGRESS_DONE), a
        call progress_print_percent
        ret

diskwrite_progress_chunk:
        ld a, (CMS_DISKWRITE_PROGRESS)
        dec a
        jr z, diskwrite_progress_dot
        ld (CMS_DISKWRITE_PROGRESS), a
        ret

diskwrite_progress_dot:
        ld a, 4
        ld (CMS_DISKWRITE_PROGRESS), a
        call progress_update
        ret

diskwrite_progress_flush:
        ld hl, (CMS_IMPORT_DONE)
        ld a, h
        or l
        ret z
        ld a, (CMS_DISKWRITE_PROGRESS)
        cp 4
        ret z
        call progress_update
        ret

progress_update:
        push hl
        push de
        push bc
        ld a, (CMS_DEBUG_MODE)
        or a
        jr nz, progress_update_done
        ld a, (CMS_PROGRESS_DONE)
        ld c, a
        ld a, (CMS_PROGRESS_TOTAL)
        cp c
        jr z, progress_update_print
        ld a, c
        inc a
        ld (CMS_PROGRESS_DONE), a

progress_update_print:
        call progress_backspace_percent
        call progress_print_percent
progress_update_done:
        pop bc
        pop de
        pop hl
        ret

progress_backspace_percent:
        ld b, 4

progress_backspace_loop:
        ld a, CHAR_BS
        call TXT_OUTPUT
        djnz progress_backspace_loop
        ret

progress_print_percent:
        call progress_calculate_percent
        call progress_print_percent_value
        ret

progress_calculate_percent:
        ld a, (CMS_PROGRESS_DONE)
        ld b, a
        ld hl, 0
        ld de, 100

progress_percent_multiply:
        ld a, b
        or a
        jr z, progress_percent_divide
        add hl, de
        dec b
        jr progress_percent_multiply

progress_percent_divide:
        ld a, (CMS_PROGRESS_TOTAL)
        ld c, a
        ld b, 0

progress_percent_divide_loop:
        ld a, h
        or a
        jr nz, progress_percent_subtract
        ld a, l
        cp c
        jr c, progress_percent_done

progress_percent_subtract:
        ld a, l
        sub c
        ld l, a
        ld a, h
        sbc a, 0
        ld h, a
        inc b
        jr progress_percent_divide_loop

progress_percent_done:
        ld a, b
        ret

progress_print_percent_value:
        cp 100
        jr nz, progress_print_under_100
        ld a, "1"
        call TXT_OUTPUT
        ld a, "0"
        call TXT_OUTPUT
        ld a, "0"
        call TXT_OUTPUT
        ld a, "%"
        call TXT_OUTPUT
        ret

progress_print_under_100:
        ld b, 0

progress_print_tens_loop:
        cp 10
        jr c, progress_print_digits
        sub 10
        inc b
        jr progress_print_tens_loop

progress_print_digits:
        push af
        ld a, " "
        call TXT_OUTPUT
        ld a, b
        or a
        jr nz, progress_print_tens
        ld a, " "
        jr progress_print_tens_done

progress_print_tens:
        ld a, b
        add a, "0"

progress_print_tens_done:
        call TXT_OUTPUT
        pop af
        add a, "0"
        call TXT_OUTPUT
        ld a, "%"
        call TXT_OUTPUT
        ret

print_progress_newline:
        ld a, (CMS_DEBUG_MODE)
        or a
        ret nz
        ld a, (CMS_PROGRESS_SEEN)
        or a
        ret z
        ld hl, msg_newline
        call print_string
        ret

msg_intro:
        db " CPC MiSTer Share "
        include "build/cpc_mister_share_version.inc"
        db 13, 10, 13, 10, 0

msg_about:
        db "CPC MiSTer Share "
        include "build/cpc_mister_share_version.inc"
        db 13, 10
        db "|about", 13, 10
        db "|cd[,", 34, "DIR", 34, "]", 13, 10
        db "|cp,", 34, "SRC", 34, ",", 34, "DST", 34, 13, 10
        db "|debug[,0|1]", 13, 10
        db "|diskread,", 34, "DISC", 34, "[,", 34, "SHARED", 34, "[,0]]", 13, 10
        db "|diskwrite,", 34, "SHARED", 34, "[,", 34, "DISC", 34, "]", 13, 10
        db "|exec,", 34, "FILE", 34, 13, 10
        db "|hexdump,", 34, "FILE", 34, 13, 10
        db "|loadm,", 34, "FILE", 34, "[,&ADDR]", 13, 10
        db "|ls[,", 34, "DIR", 34, "]", 13, 10
        db "|mkdir,", 34, "DIR", 34, 13, 10
        db "|mv,", 34, "OLD", 34, ",", 34, "NEW", 34, 13, 10
        db "|pwd", 13, 10
        db "|rm,", 34, "FILE", 34, 13, 10
        db "|savem,", 34, "FILE", 34, ",&ADDR,&LEN", 13, 10
        db "|stat,", 34, "FILE", 34, 13, 10
        db "|type,", 34, "FILE", 34, 13, 10, 0

msg_reading:
        db "Reading: ", 0

msg_writing:
        db "Writing: ", 0

msg_debug_usage:
        db "Usage: |debug[,0|1]", 13, 10, 0

msg_debug_on:
        db "Debug ON", 13, 10, 0

msg_debug_off:
        db "Debug OFF", 13, 10, 0

msg_ls_usage:
        db "Usage: |ls,", 34, "DIR", 34, 13, 10, 0

msg_cd_usage:
        db "Usage: |cd,", 34, "DIR", 34, 13, 10, 0

msg_pwd_usage:
        db "Usage: |pwd", 13, 10, 0

msg_type_usage:
        db "Usage: |type,", 34, "FILE.TXT", 34, 13, 10, 0

msg_dump_usage:
        db "Usage: |hexdump,", 34, "FILE.BIN", 34, 13, 10, 0

msg_info_usage:
        db "Usage: |stat,", 34, "FILE.BIN", 34, 13, 10, 0

msg_mkdir_usage:
        db "Usage: |mkdir,", 34, "DIR", 34, 13, 10, 0

msg_mv_usage:
        db "Usage: |mv,", 34, "OLD", 34, ",", 34, "NEW", 34, 13, 10, 0

msg_cp_usage:
        db "Usage: |cp,", 34, "SRC", 34, ",", 34, "DST", 34, 13, 10, 0

msg_rm_usage:
        db "Usage: |rm,", 34, "FILE", 34, 13, 10, 0

msg_import_usage:
        db "Usage: |diskread,", 34, "DISC", 34, "[,", 34, "SHARED", 34, "[,0]]", 13, 10, 0

msg_import_open_len:
        db "OPEN=", 0

msg_import_header_len:
        db " HDR=", 0

msg_import_done_len:
        db " DONE=", 0

msg_import_remain_len:
        db " REM=", 0

msg_newline:
        db 13, 10, 0

msg_import_done:
        db "Disk read OK", 13, 10, 0

msg_import_error:
        db "Disk read failed", 13, 10, 0

msg_diskwrite_usage:
        db "Usage: |diskwrite,", 34, "SHARED", 34, "[,", 34, "DISC", 34, "]", 13, 10, 0

msg_diskwrite_done:
        db "Disk write OK", 13, 10, 0

msg_diskwrite_error:
        db "Disk write failed", 13, 10, 0

msg_load_usage:
        db "Usage: |loadm,", 34, "FILE.BIN", 34, ",&8000", 13, 10, 0

msg_load_done:
        db "Loaded", 13, 10, 0

msg_load_error:
        db "Load failed", 13, 10, 0

msg_save_usage:
        db "Usage: |savem,", 34, "FILE.BIN", 34, ",&4000,&0100", 13, 10, 0

msg_save_done:
        db "Saved", 13, 10, 0

msg_save_error:
        db "Save failed", 13, 10, 0

msg_loadh_usage:
        db "Usage: |exec,", 34, "FILE.BIN", 34, 13, 10, 0

msg_loadh_basic_done:
        db 13, 10, "Loaded BASIC - type RUN", 13, 10, 0

; Expansion ROM images are 16KB.  Pad unused space with &FF, the normal erased
; EPROM byte value.  The build script assembles this as a raw binary suitable
; for MiSTer's .eXX expansion ROM loader.
        ds &4000 - ($ - KL_ROM_BASE), &FF
