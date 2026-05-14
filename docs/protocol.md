# CPC MiSTer Mass Storage Protocol Draft

This protocol is intentionally small. It is a proposed mailbox between CPC Z80
code and FPGA logic, designed to be extended later.

Stage 1 does not use this protocol. The current ROM only registers `|HELLO` and
prints through the CPC firmware.

## Goals

- Support folder-backed storage from MiSTer in a later stage.
- Keep FPGA logic small.
- Keep the CPC ROM easy to debug.
- Avoid emulating STM32/ESP hardware from the real M4 board.

## Non-goals

- Full M4 compatibility.
- Network access.
- Web UI.
- Firmware flashing.
- AMSDOS interception in the early stages.
- Any HPS communication in Stage 1.

## Proposed ports

These ports are reserved as a working proposal for Stage 2 and later. They are
documented here and in `rom/m4s_protocol.inc`, but Stage 1 ROM code must not
read or write them.

| Port | Name    | Direction | Meaning |
|------|---------|-----------|---------|
| FBD0 | DATA    | R/W       | Byte stream payload in/out |
| FBD1 | STATUS  | R         | Busy/ready/error/data flags |
| FBD2 | COMMAND | W         | Command selector, starts transaction |
| FBD3 | PARAM   | W         | Optional length, page, or argument byte |

Actual port selection must be checked against the current Amstrad core I/O
decode and CPC expansion conventions before any RTL integration is treated as
stable.

## STATUS bits

```text
bit 0: DATA_READY     FPGA has a byte for CPC to read
bit 1: CAN_WRITE      FPGA can accept another byte from CPC
bit 2: BUSY           Command is in progress
bit 3: ERROR          Last command failed
bit 4: END_OF_STREAM  No more bytes for current read response
bit 5-7: reserved
```

## Proposed commands

```text
00 NOP
01 PING
02 DIR_BEGIN
03 CD
04 LOAD_OPEN
05 LOAD_READ
06 SAVE_OPEN
07 SAVE_WRITE
08 CLOSE
09 GET_CWD
```

## Stage 1 behaviour

No mailbox behaviour exists in Stage 1.

Implemented ROM behaviour:

```basic
|HELLO
```

prints:

```text
M4S ROM OK
```

## Stage 2 target behaviour

Stage 2 should prove the mailbox path with a hardcoded response before any host
filesystem work is attempted.

Suggested first command:

```text
01 PING
```

Suggested response:

```text
M4S OK\r\n\0
```

Suggested next command:

```text
02 DIR_BEGIN
```

Suggested mock response:

```text
M4S MOCK DIR\r\nREADME.TXT\r\nHELLO.BAS\r\n\0
```

## Later host-backed behaviour

The FPGA mailbox should eventually hand off command requests to the MiSTer HPS
side. Prefer keeping file path parsing and filesystem access outside the FPGA
fabric where possible.
