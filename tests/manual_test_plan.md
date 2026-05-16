# Manual Test Plan

This checklist is for the shared-folder tester build.  It assumes the matching
ROM, Amstrad core, and Main_MiSTer binary are installed.

## 1. Boot and Command Registration

1. Boot the modified Amstrad core.
2. Confirm the boot screen includes:

```text
 CPC MiSTer Share v0.1 installed
```

The exact version is generated from git at build time, so tester builds may
include a suffix such as `-dirty` or `-1-gabcdef`.

3. Run:

```basic
|about
```

Expected:

- `|about` prints the stage and a readable command list.
- `|HELLO` is not present.

## 2. Shared Folder Discovery

1. Create a `shared` folder beside the resolved Amstrad games folder, for
   example `/media/fat/games/Amstrad/shared` or
   `/media/usb0/games/Amstrad/shared`.
2. Put a small text file and binary file in it.
3. Run:

```basic
|ls
|pwd
```

Expected:

- `|ls` shows the shared-folder contents.
- `|pwd` shows `/`.
- If the folder is missing, the command reports that clearly instead of
  hanging.

## 3. Navigation and Path Handling

Create a nested directory such as `games/dizzy`, then run:

```basic
|ls,"games"
|cd,"games"
|pwd
|ls,"dizzy"
|cd,"dizzy"
|pwd
|cd,".."
|pwd
|cd
|pwd
```

Expected:

- `|ls,"DIR"` lists that directory without changing the current directory.
- Relative paths, absolute paths starting with `/`, and `..` work.
- `|cd` with no argument returns to `/`.
- Paths cannot escape the shared-folder root.

## 4. Text, Binary, and Metadata

Run:

```basic
|type,"hello.txt"
|hexdump,"hello.txt"
|stat,"hello.txt"
|stat,"headered.bin"
```

Expected:

- `|type` prints text and displays LF line endings correctly on the CPC.
- `|hexdump` prints offset-prefixed ASCII hex.
- `|stat` reports `AMSDOS: NO HEADER` for headerless files.
- `|stat` reports load, entry, length, and checksum details for valid AMSDOS
  files.

## 5. Shared Folder File Management

Run:

```basic
|mkdir,"tmp"
|cp,"hello.txt","tmp/hello.txt"
|cp,"hello.txt","tmp"
|mv,"tmp/hello.txt","tmp/renamed.txt"
|rm,"tmp/renamed.txt"
|ls,"tmp"
```

Expected:

- `|mkdir` creates the directory.
- `|cp` can copy to a file path or to an existing directory.
- `|mv` renames files or directories.
- `|rm` removes files and refuses directories.
- Create operations refuse to overwrite existing destinations.

## 6. Memory Save and Load

Put a recognizable byte pattern in memory, then run:

```basic
|savem,"mem.bin",&4000,&0100
|hexdump,"mem.bin"
|loadm,"mem.bin",&7000
```

Expected:

- `|savem` creates `mem.bin`.
- `|hexdump` matches the bytes from `&4000`.
- `|loadm` copies the same bytes to `&7000`.
- Saving over an existing shared file is refused.

## 7. Execute Shared AMSDOS Files

Test a missing file first:

```basic
|exec,"missing.bin"
```

Expected:

- It reports `Load failed`.
- It does not ask whether to run the file.

Then test a known-good AMSDOS binary:

```basic
|exec,"program.bin"
```

Expected:

- File metadata is printed.
- The command asks `Load and CALL entry? Y/N`.
- `N` cancels cleanly.
- `Y` loads and runs the program, or for a BASIC file prints that you should
  type `RUN`.

## 8. Disk Read

With a disk image mounted and a known file visible to CPC `CAT`, run:

```basic
|diskread,"DISCFILE"
|diskread,"DISCFILE","copy.bin"
|diskread,"DISCFILE","payload.bin",0
```

Expected:

- The command shows `Reading:   0%` and updates percentage progress.
- It ends with `Disk read OK`.
- The default forms preserve the AMSDOS header in the shared file.
- The third form strips the header.
- Existing shared destinations are refused with a useful error.

## 9. Disk Write

Use an AMSDOS-headered file in the shared folder and a blank or disposable disk
image:

```basic
|diskwrite,"copy.bin"
|diskwrite,"copy.bin","OTHER"
CAT
```

Expected:

- The command shows `Writing:   0%` and updates percentage progress.
- It ends with `Disk write OK`.
- The one-argument form uses the final shared path component as the disk name.
- The two-argument form uses the explicit disk name.
- `CAT` shows the file on the disk.

For executable binaries, reset the CPC after writing and verify `RUN"NAME"` from
the disk works.

## 10. Round Trip Verification

For a larger AMSDOS file:

1. `|diskread` it from disk to shared.
2. Reset the CPC.
3. `|diskwrite` it from shared to a different disk image.
4. Reset the CPC.
5. `|diskread` the new disk file back to a second shared filename.
6. Compare the two shared files on the host.

Expected:

- Payload bytes match.
- Header fields and checksum remain valid.
- Header residue outside meaningful AMSDOS fields does not have to match
  byte-for-byte.

## 11. Debug Mode

Run:

```basic
|debug
|debug,1
|diskread,"DISCFILE","debug.bin"
|debug,0
```

Expected:

- `|debug` shows the current state.
- `|debug,1` enables extra diskread diagnostics such as `OPEN=`, `HDR=`,
  `DONE=`, and `REM=`.
- `|debug,0` returns to normal progress output.

## Failure Reports

When reporting an issue, include:

- exact command typed
- exact screen output
- file names and whether they contain an AMSDOS header
- mounted disk image type if disk commands were involved
- whether `|debug,1` was enabled
- whether the CPC crashed, reset, hung, or returned to BASIC
