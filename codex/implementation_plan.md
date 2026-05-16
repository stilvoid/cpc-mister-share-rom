# CPC MiSTer Share Implementation Plan

## Current Goal

CPC MiSTer Share adds an explicit shared-folder utility to the MiSTer Amstrad
CPC core.  It uses a CPC expansion ROM, a small FPGA mailbox, and an
Amstrad-specific Main_MiSTer helper.

The current design deliberately keeps the feature explicit: users call RSX
commands such as `|ls`, `|type`, `|diskread`, and `|diskwrite`.  It does not
try to intercept normal AMSDOS commands such as `CAT`, `LOAD`, or `SAVE`.

## Implemented

- Expansion ROM with `CPC MiSTer Share` sign-on and `|about`.
- Live shared-folder listing through Main_MiSTer and the Amstrad core mailbox.
- Shared-folder navigation: `|ls`, `|cd`, and `|pwd`.
- Shared-folder reads: `|type`, `|hexdump`, `|stat`, `|loadm`, and `|exec`.
- Shared-folder writes and management: `|savem`, `|mkdir`, `|mv`, `|cp`, and
  `|rm`.
- Disk import/export through AMSDOS: `|diskread` and `|diskwrite`.
- Conservative overwrite behavior for commands that create shared files.
- Debug mode for disk-read diagnostics.

## Next Useful Work

- Broaden manual testing on different MiSTer storage layouts.
- Improve error messages where tester feedback shows ambiguity.
- Decide whether `|loadm` and `|savem` should stay in the public command set.
- Consider optional prefixed aliases if real-world RSX command collisions become
  common.
- Refactor the Main_MiSTer helper into smaller sections before an upstream PR.
- Replace ASCII-hex write requests with length-aware binary writes if larger
  host-bound transfers become a priority.

## Non-Goals For This Utility

- Transparent drive integration for normal `CAT`, `LOAD`, or `SAVE`.
- Network access.
- Recursive file management or wildcard expansion.
- Support for arbitrary hidden ROM/RAM bank dumping.
