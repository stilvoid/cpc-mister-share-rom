# Manual Test Plan

## Stage 1: Expansion ROM visible

1. Run `make` to build `build/boot.eXX`.
2. Copy to the Amstrad core's expected ROM folder using the slot filename you
   want to test, for example `boot.e09`.
3. Boot the core.
4. Confirm the boot screen includes:

```text
 M4S ROM Stage 2.1 installed

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

## Debug hints

- If `|HELLO` is unknown, debug ROM header/RSX registration first.
- If `|HELLO` works but `|M4DIR` hangs, debug port decode/status bits.
- If bytes are wrong, confirm I/O data direction and read strobe timing.
- If `|M4DIR` still prints `NO M4S INDEX`, confirm the core menu download used `Load M4S index`.
- If the core locks up, check Z80 wait-state/ack behaviour and whether I/O reads are being held too long.
