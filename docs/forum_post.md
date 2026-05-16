# Forum Post Draft

Subject: CPC MiSTer Share test build - shared folder support for Amstrad CPC

I have an experimental test build for the Amstrad CPC core that adds shared
folder support.

The feature is called **CPC MiSTer Share**.  It is an explicit RSX command set
for moving files between the CPC and a `shared` folder on MiSTer.  It also has
commands to copy files between the shared folder and the currently mounted CPC
disk image.

This is not intended to replace AMSDOS or make `CAT`/`LOAD`/`SAVE` magically
use a folder.  For now it is a utility ROM: you use commands like `|ls`,
`|type`, `|diskread`, and `|diskwrite`.

## Attached Files

This test build needs all three matching parts:

- modified Amstrad core RBF
- modified MiSTer Main binary
- CPC MiSTer Share expansion ROM

Please back up your existing files before replacing anything, especially
`/media/fat/MiSTer`.

## Installation

1. Copy the supplied Amstrad RBF to:

```text
/media/fat/_Computer/Amstrad.rbf
```

2. Copy the supplied Main binary to:

```text
/media/fat/MiSTer
```

Restart MiSTer after replacing Main.

3. Copy the supplied ROM to your Amstrad games folder as an expansion ROM.  For
example:

```text
/media/fat/games/Amstrad/boot.e09
```

If your Amstrad games folder is on USB, use that location instead, for example:

```text
/media/usb0/games/Amstrad/boot.e09
```

4. Create a folder called `shared` beside your Amstrad games folder:

```text
/media/fat/games/Amstrad/shared
```

or:

```text
/media/usb0/games/Amstrad/shared
```

5. Start the Amstrad core.  On boot you should see a line like:

```text
 CPC MiSTer Share v0.1...
```

## Basic Commands

At the BASIC prompt, try:

```basic
|about
|ls
|pwd
|cd,"folder"
|cd
|type,"readme.txt"
|hexdump,"file.bin"
|stat,"file.bin"
```

File management inside the shared folder:

```basic
|mkdir,"newdir"
|cp,"a.txt","newdir/a.txt"
|mv,"old.txt","new.txt"
|rm,"new.txt"
```

Copy a file from the currently mounted CPC disk into the shared folder:

```basic
|diskread,"DISCFILE"
|diskread,"DISCFILE","sharedname.bin"
```

The default is to preserve the AMSDOS header.  To strip the header:

```basic
|diskread,"DISCFILE","payload.bin",0
```

Copy an AMSDOS-headered shared file back to the currently mounted disk:

```basic
|diskwrite,"sharedname.bin"
|diskwrite,"sharedname.bin","DISCFILE"
```

Run an AMSDOS-headered binary from the shared folder:

```basic
|exec,"game.bin"
```

BASIC files are loaded and left ready for `LIST` or `RUN`.

## Notes And Limits

- This is experimental.  Please use disposable disk images when testing
  `|diskwrite`.
- Commands that create shared files should refuse to overwrite existing shared
  files.
- Paths are relative to the current shared directory.  A leading `/` starts from
  the shared folder root.
- `..` is supported but should not escape the shared folder.
- Some commands use 16-bit CPC-side offsets, so very large files are not the
  main target yet.
- `|savem` saves the currently visible Z80 memory range, not necessarily
  physical RAM hidden behind ROM or bank switching.

## Feedback Wanted

Please report:

- your storage layout, for example SD only or USB games folder
- whether the `shared` folder was found correctly
- exact RSX command typed
- exact screen output
- whether the CPC returned to BASIC, hung, reset, or corrupted the display
- the type of file tested: text, binary, BASIC, AMSDOS-headered, headerless
- whether disk read/write tests used a copy of a disk image

Useful first tests:

1. Put a text file in `shared` and run `|ls` then `|type,"filename.txt"`.
2. Mount a disk, run `CAT`, then try `|diskread` on one file.
3. Try `|stat` on the copied file.
4. If it is a binary, try `|exec`.
5. Try `|diskwrite` only on a disposable disk image.
