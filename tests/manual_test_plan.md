# Manual Test Plan

## Stage 1: Expansion ROM visible

1. Run `make` to build `build/boot.eXX`.
2. Copy to the Amstrad core's expected ROM folder using the slot filename you
   want to test, for example `boot.e09`.
3. Boot the core.
4. Confirm the boot screen includes:

```text
 M4S ROM Stage 4.1 installed

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
|M4DIR
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
|M4DIR
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
|M4DIR
```

Expected:

```text
M4S SHARED
```

followed by the files and folders from the shared folder.

## Stage 4A: Type a shared text file

1. Install the matching custom Main_MiSTer binary and Amstrad core.
2. Put a small text file in the resolved shared folder.
3. Start the Amstrad core and run:

```basic
|M4TYPE,"HELLO.TXT"
```

Expected:

The file contents print to the CPC screen. Bare LF line endings are displayed as
CRLF.

## Stage 4B: Dump a shared binary file

1. Install the matching custom Main_MiSTer binary and Amstrad core.
2. Put a small binary file in the resolved shared folder.
3. Start the Amstrad core and run:

```basic
|M4DUMP,"FILE.BIN"
```

Expected:

The CPC prints offset-prefixed hex rows such as:

```text
0000: 00 01 02 03
```

The output is ASCII hex, not raw binary, because the current mailbox response is
still zero-terminated.

## Debug hints

- If `|HELLO` is unknown, debug ROM header/RSX registration first.
- If `|HELLO` works but `|M4DIR` hangs, debug port decode/status bits.
- If bytes are wrong, confirm I/O data direction and read strobe timing.
- If `|M4DIR` still prints `NO M4S INDEX`, confirm the core menu download used `Load M4S index`.
- If live listing does not update, confirm the custom Main_MiSTer binary is
  running and that the Amstrad core has the `m4s_hps_ext` `EXT_BUS` wiring.
- If `|M4TYPE` or `|M4DUMP` hangs, check the CPC-to-HPS request status path in
  `m4s_mailbox` and `m4s_hps_ext`.
- If the core locks up, check Z80 wait-state/ack behaviour and whether I/O reads are being held too long.
