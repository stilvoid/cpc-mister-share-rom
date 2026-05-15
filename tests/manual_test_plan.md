# Manual Test Plan

## Stage 1: Expansion ROM visible

1. Run `make` to build `build/boot.eXX`.
2. Copy to the Amstrad core's expected ROM folder using the slot filename you
   want to test, for example `boot.e09`.
3. Boot the core.
4. Confirm the boot screen includes:

```text
 M4S ROM Stage 4.12 installed

```

5. Run:

```basic
|HELLO
```

Expected:

```text
M4S ROM OK
```

## Stage 2: Mailbox fallback directory

Run:

```basic
|ls
```

Expected:

```text
NO M4S INDEX
```

## Stage 3A: Preloaded M4S index

1. Open the Amstrad core menu.
2. Select `Load M4S index`.
3. Choose `examples/m4s-index.txt` or another plain text index file.
4. Run:

```basic
|ls
```

Expected when using the example file:

```text
M4S INDEX
README.TXT
HELLO.BAS
GAMES
```

## Stage 3B: Live shared folder listing

1. Install the matching custom Main_MiSTer binary and Amstrad core.
2. Create files in MiSTer's configured `shared` folder, or leave
   `shared_folder` empty to use the default `shared` folder.
3. Start the Amstrad core.
4. Run:

```basic
|ls
```

Expected:

```text
M4S SHARED
```

followed by the files and folders from the shared folder.

## Stage 4: Navigate shared folders

1. Install the matching custom Main_MiSTer binary and ROM.
2. Create a child directory under the resolved shared folder.
3. Run:

```basic
|ls
|cd,"GAMES"
|ls
|ls,"DIZZY"
|cd,"DIZZY"
|ls
|cd,".."
|ls
|ls,"/GAMES/DIZZY"
|cd,"/GAMES/DIZZY"
|ls
|cd
|ls
```

Expected:

`|cd,"GAMES"` prints `CWD: /GAMES`, nested and parent paths update `CWD`
correctly, `|ls,"DIZZY"` and `|ls,"/GAMES/DIZZY"` list those folders without
changing `CWD`, file commands resolve relative to that directory, and bare
`|cd` resets to `CWD: /`.

## Stage 4A: Type a shared text file

1. Install the matching custom Main_MiSTer binary and Amstrad core.
2. Put a small text file in the resolved shared folder and another in its
   parent folder.
3. Start the Amstrad core and run:

```basic
|type,"HELLO.TXT"
|type,"../PARENT.TXT"
```

Expected:

The file contents print to the CPC screen. Bare LF line endings are displayed as
CRLF.

## Stage 4B: Dump a shared binary file

1. Install the matching custom Main_MiSTer binary and Amstrad core.
2. Put a small binary file in the resolved shared folder.
3. Start the Amstrad core and run:

```basic
|hexdump,"FILE.BIN"
```

Expected:

The CPC prints offset-prefixed hex rows such as:

```text
0000: 00 01 02 03
```

The output is ASCII hex, not raw binary, because the current mailbox response is
still zero-terminated.

## Stage 4C: Inspect shared file metadata

1. Install the matching custom Main_MiSTer binary and ROM.
2. Put an AMSDOS binary file in the resolved shared folder.
3. Start the Amstrad core and run:

```basic
|stat,"FILE.BIN"
```

Expected for a file with a valid AMSDOS header:

```text
AMSDOS: HEADER OK
LOAD: &....
ENTRY: &....
```

Headerless files should print `AMSDOS: NO HEADER`.

## Stage 4D: Load a shared binary file

1. Install the matching custom Main_MiSTer binary, Amstrad core, and ROM.
2. Put a small binary file in the resolved shared folder and another in its
   parent folder.
3. Start the Amstrad core and run:

```basic
|loadm,"FILE.BIN"
```

Expected:

```text
Loaded
```

Use a monitor, BASIC `PEEK`, or a small test program to confirm the bytes at
`&4000` match the source file.

Then try an explicit destination:

```basic
|loadm,"FILE.BIN",&8000
|loadm,"../PARENT.BIN",&7000
```

Confirm the bytes at `&8000` and `&7000` match the source files. The proof
command reads in 512-byte chunks, and the file offset is currently 16-bit.

## Stage 4E: Load and run an AMSDOS binary

1. Install the matching custom Main_MiSTer binary and ROM.
2. Put an AMSDOS binary with a valid header in the resolved shared folder.
3. Start the Amstrad core and run:

```basic
|exec,"FILE.BIN"
```

Expected:

The command prints file metadata, prompts for confirmation, then loads the
payload at the AMSDOS load address and jumps to the AMSDOS entry address when
you press `Y`.

## Stage 4F: Save a memory range to the shared folder

1. Install the matching custom Main_MiSTer binary and ROM.
2. Start the Amstrad core and put a recognizable byte pattern in memory.
3. Run:

```basic
|savem,"OUT.BIN",&4000,&0100
|savem,"../PARENT.OUT",&4000,&0100
```

Expected:

```text
Saved
```

Confirm `OUT.BIN` appears in the current shared folder, `PARENT.OUT` appears in
the parent folder, and both compare with the bytes at `&4000`.
`|hexdump,"OUT.BIN"` should show the saved data too.

## Stage 4G: Create a shared folder directory

1. Install the matching custom Main_MiSTer binary and ROM.
2. Start the Amstrad core and run:

```basic
|mkdir,"NEW"
|ls
```

Expected:

`|mkdir,"NEW"` prints `Created: NEW`, and `|ls` shows `NEW/`.

## Stage 4H: Rename a shared folder file or directory

1. Install the matching custom Main_MiSTer binary and ROM.
2. Create `OLD.BIN` in the current shared folder.
3. Start the Amstrad core and run:

```basic
|mv,"OLD.BIN","NEW.BIN"
|ls
```

Expected:

`|mv,"OLD.BIN","NEW.BIN"` prints `Renamed: OLD.BIN -> NEW.BIN`, `|ls` shows
`NEW.BIN`, and the command refuses to overwrite an existing destination.

## Stage 4I: Remove a shared folder file

1. Install the matching custom Main_MiSTer binary and ROM.
2. Create `DELETE.ME` in the current shared folder.
3. Start the Amstrad core and run:

```basic
|rm,"DELETE.ME"
|ls
```

Expected:

`|rm,"DELETE.ME"` prints `Removed: DELETE.ME`, and `|ls` no longer shows it.
Directories should be refused.

## Debug hints

- If `|HELLO` is unknown, debug ROM header/RSX registration first.
- If `|HELLO` works but `|ls` hangs, debug port decode/status bits.
- If bytes are wrong, confirm I/O data direction and read strobe timing.
- If `|ls` still prints `NO M4S INDEX`, confirm the core menu download used `Load M4S index`.
- If live listing does not update, confirm the custom Main_MiSTer binary is
  running and that the Amstrad core has the `m4s_hps_ext` `EXT_BUS` wiring.
- If `|cd`, `|type`, `|hexdump`, `|stat`, `|loadm`, `|exec`, `|savem`, `|mkdir`, `|mv`, or `|rm` hangs, check the CPC-to-HPS request status path in
  `m4s_mailbox` and `m4s_hps_ext`.
- If the core locks up, check Z80 wait-state/ack behaviour and whether I/O reads are being held too long.
