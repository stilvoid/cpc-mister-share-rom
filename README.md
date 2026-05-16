# CPC MiSTer Share ROM

Experimental shared-folder support for the MiSTer Amstrad CPC core.

This is no longer trying to be an M4 board clone.  The current goal is a useful
RSX command set that lets a CPC program or user move data between the CPC and a
MiSTer `shared` folder, plus explicit commands for copying files to and from the
currently mounted AMSDOS disk.

The current ROM identifies itself as:

```text
 CPC MiSTer Share 4.14 installed
```

## Requirements

The tester build needs three matching pieces:

- this ROM, installed as an Amstrad expansion ROM such as
  `games/Amstrad/boot.e09`
- the matching modified `Amstrad_MiSTer` core/RBF
- the matching modified `Main_MiSTer` binary

The ROM can boot without the modified core/Main, but the shared-folder commands
will not work usefully.

## Shared Folder

Create a folder called `shared` next to the Amstrad core's resolved games
folder.  The host side uses MiSTer's normal path resolution, so this follows the
same USB/SD precedence as loading disk images.

Common examples:

```text
/media/fat/games/Amstrad/shared
/media/usb0/games/Amstrad/shared
```

Paths passed to RSX commands are relative to the current shared directory.
Leading `/` starts from the shared-folder root.  `..` is supported but is kept
inside the shared-folder tree.

## Building and Installing

Build only the ROM:

```sh
make build/boot.eXX
```

Build the modified Main binary locally:

```sh
make main
```

Build the core on the configured remote Quartus host:

```sh
make remote-core
```

Build and install all three pieces:

```sh
make install
```

Useful Makefile variables:

```sh
MISTER_HOST=root@mister
MISTER_ROM=/media/usb0/games/Amstrad/boot.e09
MISTER_CORE=/media/fat/_Computer/Amstrad.rbf
MISTER_MAIN=/media/fat/MiSTer
EC2_INSTANCE_ID=i-...
AWS_REGION=eu-west-2
```

`make install-main` stages the new Main binary as `MiSTer.new`, backs up the
existing binary as `MiSTer.old`, then swaps the new binary into place.  Restart
MiSTer after replacing Main.

## Commands

Run `|about` on the CPC for the ROM's built-in command summary.

```basic
|about
|cd[,"DIR"]
|cp,"SRC","DST"
|debug[,0|1]
|diskread,"DISC"[,"SHARED"[,0]]
|diskwrite,"SHARED"[,"DISC"]
|exec,"FILE"
|hexdump,"FILE"
|loadm,"FILE"[,&ADDR]
|ls[,"DIR"]
|mkdir,"DIR"
|mv,"OLD","NEW"
|pwd
|rm,"FILE"
|savem,"FILE",&ADDR,&LEN
|stat,"FILE"
|type,"FILE"
```

### Shared Folder Commands

- `|ls` lists the current shared directory.
- `|ls,"DIR"` lists another shared directory without changing `|pwd`.
- `|cd` returns to the shared-folder root.
- `|cd,"DIR"` changes the current shared directory.
- `|pwd` prints the current shared directory.
- `|type,"FILE"` prints a text file, converting LF line endings for the CPC.
- `|hexdump,"FILE"` prints file bytes as offset-prefixed hex.
- `|stat,"FILE"` prints file size and AMSDOS header details when present.
- `|loadm,"FILE"` loads raw bytes to `&4000`.
- `|loadm,"FILE",&ADDR` loads raw bytes to an explicit address.
- `|savem,"FILE",&ADDR,&LEN` saves a memory range to the shared folder.
- `|exec,"FILE"` reads an AMSDOS header, prompts, loads, and jumps or prepares
  a BASIC file for `RUN`.
- `|mkdir,"DIR"` creates a shared directory.
- `|mv,"OLD","NEW"` renames a shared file or directory.
- `|cp,"SRC","DST"` copies within the shared folder.
- `|rm,"FILE"` removes a shared file.

Commands that create shared files refuse to overwrite an existing destination.

### Disk Commands

`|diskread` copies from the currently mounted AMSDOS disk into the shared
folder:

```basic
|diskread,"DISCFILE"
|diskread,"DISCFILE","shared/path.bin"
|diskread,"DISCFILE","shared/path.bin",0
```

By default, `|diskread` preserves the AMSDOS header in the shared copy.  Passing
`0` as the third argument strips the header and writes only the payload.
Existing shared destinations are refused.

`|diskwrite` copies an AMSDOS-headered shared file to the currently mounted
AMSDOS disk:

```basic
|diskwrite,"shared/path.bin"
|diskwrite,"shared/path.bin","DISCFILE"
```

The one-argument form uses the final component of the shared path as the disk
filename.

Both disk commands show percentage progress in normal mode.

### Debug Mode

```basic
|debug
|debug,1
|debug,0
```

Debug mode is off by default.  It currently enables extra `|diskread`
diagnostics such as AMSDOS open/header/done/remaining counters.

## Known Limits

- This is an explicit RSX shared-folder system, not transparent AMSDOS drive
  integration.
- It is not currently M4 ROM compatible and does not provide SymbOS mass
  storage compatibility.
- No wildcard or recursive operations yet.
- Some operations use 16-bit CPC-side offsets or lengths.
- `|exec` deliberately jumps into loaded CPC code; bad or incompatible binaries
  can reset or crash the CPC.
- Some host-side disk tools, including `iDSK` in earlier testing, may not be a
  reliable verifier for large files.  Prefer CPC `CAT`/`RUN` and ROM
  diskread/diskwrite round trips when testing.

## Tester Checklist

1. Boot the modified core and confirm the stage 4.14 sign-on appears.
2. Run `|about` and confirm the command list is readable.
3. Create files in `shared`, then run `|ls`, `|cd`, and `|pwd`.
4. Try `|type`, `|hexdump`, and `|stat` on text, binary, headered, and
   headerless files.
5. Try `|mkdir`, `|cp`, `|mv`, and `|rm`, including overwrite refusal.
6. Try `|savem` and `|loadm` with a small known memory pattern.
7. Try `|diskread` from a mounted disk into `shared`.
8. Try `|exec` on the copied file if it is an executable AMSDOS binary.
9. Try `|diskwrite` to a blank disk and verify with CPC `CAT` or `RUN`.
10. Report the exact command, screen output, file names, and whether debug mode
    was enabled for any failure.
