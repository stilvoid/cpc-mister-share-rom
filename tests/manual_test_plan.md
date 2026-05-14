# Manual Test Plan

## Stage 1: Expansion ROM visible

1. Run `make` to build `build/boot.eXX`.
2. Copy to the Amstrad core's expected ROM folder using the slot filename you
   want to test, for example `boot.e09`.
3. Boot the core.
4. Confirm the boot screen includes:

```text
 M4S ROM Stage 1 installed

```

5. Run:

```basic
|HELLO
```

Expected:

```text
M4S ROM OK
```

## Stage 2: Mailbox mock directory

Run:

```basic
|M4DIR
```

Expected:

```text
M4S MOCK DIR
README.TXT
HELLO.BAS
```

## Debug hints

- If `|HELLO` is unknown, debug ROM header/RSX registration first.
- If `|HELLO` works but `|M4DIR` hangs, debug port decode/status bits.
- If bytes are wrong, confirm I/O data direction and read strobe timing.
- If the core locks up, check Z80 wait-state/ack behaviour and whether I/O reads are being held too long.
