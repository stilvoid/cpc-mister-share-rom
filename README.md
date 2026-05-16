# CPC MiSTer Share ROM

ROM source for CPC MiSTer Share, an Amstrad CPC expansion ROM that exposes
shared-folder RSX commands when used with the matching MiSTer Main and
Amstrad core changes.

Build only the ROM:

```sh
make
```

The output is written to:

```text
build/boot.eXX
```

The version string is generated at build time with
`git describe --tags --dirty --always`.
