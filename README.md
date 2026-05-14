# CPC MiSTer Mass Storage Scaffold

Experimental scaffold for adding a folder-backed mass-storage device to the
MiSTer Amstrad CPC core.

This is deliberately not a full M4 clone. Stage 1 was only a tiny CPC expansion
ROM that proves the CPC can see the ROM and dispatch an RSX command. Stage 2
adds a minimal CPC-to-FPGA mailbox. Stage 3A preloads a text directory index
through MiSTer's existing file download path.

## Stage 1-3A status

Implemented:

- A valid 16KB CPC background expansion ROM source in `rom/m4s_rom.asm`.
- A boot sign-on line:

```text
 M4S ROM Stage 2.1 installed

```

- One RSX command:

```basic
|HELLO
```

Expected output:

```text
M4S ROM OK
```

- A second RSX command:

```basic
|M4DIR
```

Expected output before an index file is loaded:

```text
NO M4S INDEX
```

Expected output after loading `examples/m4s-index.txt` through the core menu's
`Load M4S index` item:

```text
M4S INDEX
README.TXT
HELLO.BAS
GAMES
```

- A mock FPGA mailbox in `rtl/m4s_mailbox.sv` for commands `PING` and
  `DIR_BEGIN`.
- A MiSTer core menu entry `Load M4S index` that accepts a plain text file and
  streams it back via `|M4DIR`.

Not implemented yet:

- Real storage commands.
- HPS communication.
- Live host folder enumeration.
- AMSDOS interception.
- M4 compatibility.

## How CPC expansion ROMs work

The Amstrad CPC maps expansion ROMs into the upper 16KB address range,
`&C000` to `&FFFF`. Each ROM image can therefore be up to 16KB.

At boot, the CPC firmware walks available ROM slots and examines the ROM prefix
at `&C000`. A background ROM has type byte `1`. Its prefix also points to an
external command name table and a matching jumpblock.

For a background ROM, jumpblock entry 0 is the power-up initialisation routine.
If that routine returns with carry set, the firmware registers the ROM as a
provider of external commands. BASIC can then call suitable command names with
the RSX bar syntax, for example `|HELLO`.

In this Stage 1 ROM:

- Entry 0 is `rom_init`, which returns success and allocates no RAM.
- Entry 1 is `rsx_hello`, which prints `M4S ROM OK`.
- Printing uses the standard CPC firmware `TXT OUTPUT` call at `&BB5A`.

## How MiSTer loads `.eXX` ROMs

MiSTer's Amstrad core can load CPC expansion ROM images as `.eXX` files, where
`XX` is the ROM slot number in hexadecimal. For example:

- `boot.eC0`
- `boot.eC1`
- `boot.e01`

The ROM image itself is still a raw 16KB CPC expansion ROM. The `.eXX` suffix is
the MiSTer-side loader convention that tells the core which expansion ROM slot
to populate.

Use a non-conflicting slot for local testing. This scaffold builds
`build/boot.eXX` by default; rename or install it as the slot filename you want
to test, such as `boot.e09`.

## Build instructions

Install `pasmo`, then run:

```sh
make
```

On Debian/Ubuntu:

```sh
sudo apt install pasmo
```

The default output is:

```text
build/boot.eXX
```

To choose a different output slot/name:

```sh
make ROM_OUT=build/boot.e09
```

The Makefile verifies that the final image is exactly 16384 bytes. The legacy
`scripts/build_rom.sh` wrapper still works and delegates to `make`.

## Where to place the ROM on MiSTer

Place the built `.eXX` file in the Amstrad core's games folder:

```text
/media/fat/games/Amstrad/
```

If you use USB storage or another MiSTer games path, use the equivalent
`games/Amstrad/` directory for that storage device.

Then start or reset the Amstrad core so the expansion ROM is visible during the
CPC firmware ROM walk.

The `install` target deploys both the expansion ROM and the built core:

```sh
make install
```

Defaults:

```text
MISTER_HOST=root@mister
MISTER_ROM=/media/usb0/games/Amstrad/boot.e09
MISTER_CORE=/media/fat/Amstrad.rbf
CORE_RBF=build/remote/Amstrad.rbf
```

Override these if your MiSTer uses different paths.

## Remote core build

If your development machine cannot run Quartus, use an x86_64 remote builder.
See `docs/remote_build.md` for the EC2/Docker workflow used to compile the
modified `Amstrad_MiSTer` core.

## Stage 3A M4S index loading

This stage does not enumerate MiSTer's `shared` folder live. Instead, it uses
the Amstrad core's existing menu file download mechanism to preload a small text
index into FPGA RAM.

1. Copy or create a plain text index file on MiSTer, for example:

```text
M4S INDEX
README.TXT
HELLO.BAS
GAMES
```

2. Open the Amstrad core menu.
3. Select `Load M4S index`.
4. Choose the text file.
5. In BASIC, run:

```basic
|M4DIR
```

The index buffer is currently 2048 bytes and is treated as zero-terminated. If
no index has been loaded, `|M4DIR` prints `NO M4S INDEX`.

## Testing `|HELLO` in BASIC

1. Build the ROM:

```sh
make
```

2. Copy `build/boot.eXX` to `games/Amstrad/` on MiSTer using the slot filename
   you want to test, for example `boot.e09`.
3. Start or reset the Amstrad core.
4. Confirm the boot screen includes ` M4S ROM Stage 2.1 installed` followed by a
   blank line.
5. At the BASIC prompt, type:

```basic
|HELLO
```

Expected output:

```text
M4S ROM OK
```

If BASIC reports an unknown command, debug ROM loading, slot selection, and the
ROM prefix before looking at any future mailbox work.

## Stage 2 notes

Stage 2 should add the simplest possible CPC-to-core mailbox path, still without
host filesystem access. The ROM can then grow a second command such as `|M4DIR`
that requests a hardcoded response from FPGA-side logic.

Keep the boundary clear:

- The current Stage 1 ROM must not touch mailbox ports.
- The proposed mailbox ports stay documented in `docs/protocol.md`.
- Host filesystem enumeration belongs after the mock mailbox is working.

## Repository layout

```text
rtl/m4s_mailbox.sv           FPGA-side command/status/data mailbox scaffold
rom/m4s_rom.asm              Stage 1 CPC expansion ROM
rom/m4s_protocol.inc         Future Z80-side protocol constants
Makefile                     ROM build and install rules
scripts/build_rom.sh         Compatibility wrapper around make
docs/protocol.md             CPC <-> FPGA mailbox protocol proposal
codex/implementation_plan.md Detailed implementation checklist
tests/manual_test_plan.md    Manual smoke tests on MiSTer
```
