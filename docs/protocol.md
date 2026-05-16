# CPC MiSTer Share Protocol

CPC MiSTer Share uses a small mailbox between the CPC Z80, the Amstrad core,
and Main_MiSTer.  The CPC ROM writes requests to four I/O ports, the FPGA stores
the request, and the HPS side answers by filling the response stream.

The protocol is intentionally project-specific.  It is not an M4 board protocol
and does not try to emulate the M4 hardware stack.

## Ports

| Port | Name    | Direction | Meaning |
|------|---------|-----------|---------|
| FBD0 | DATA    | R/W       | Byte stream payload in/out |
| FBD1 | STATUS  | R         | Busy/ready/error/data flags |
| FBD2 | COMMAND | W         | Command selector, starts transaction |
| FBD3 | PARAM   | W         | Optional length, page, or argument byte |

## Status Bits

```text
bit 0: DATA_READY     FPGA has a byte for CPC to read
bit 1: CAN_WRITE      FPGA can accept another byte from CPC
bit 2: BUSY           Command is in progress
bit 3: ERROR          Last command failed
bit 4: END_OF_STREAM  No more bytes for current read response
bit 5-7: reserved
```

## ROM Commands

The ROM constants live in `rom/cpc_mister_share_protocol.inc`.

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
0A REQ_BEGIN
0B TYPE
```

Most current RSX commands use `REQ_BEGIN` followed by an ASCII request string.
The final `TYPE` command starts the response stream.  Chunked binary operations
use length-prefixed responses so zero bytes can be transferred safely.

## HPS Commands

The Amstrad core sends these command bytes over `EXT_BUS` for Main_MiSTer:

```text
70 DIR_BEGIN
71 DIR_WRITE
72 REQ_STATUS
73 REQ_READ
74 REQ_ACK
77 RESP_DONE
```

Main_MiSTer polls pending requests, resolves shared-folder paths using MiSTer's
normal path precedence, and writes text or binary response bytes back through
the core.

## Fallback Responses

The FPGA keeps tiny fallback responses for early bring-up or missing HPS data:

```text
CMS OK\r\n\0
NO SHARE INDEX\r\n\0
```

Normal tester builds should use the live Main_MiSTer path rather than the
fallback directory index.
