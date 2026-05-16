* Keep refusing overwrites consistently.
    Commands that create files should fail clearly if the destination already
    exists. Users can delete, rename, or choose another destination explicitly.

* Review command ergonomics for consistency.
    Make path handling, default filenames, relative paths, case-insensitive
    reads, and destination behaviour feel consistent across:
    ls, cd, pwd, type, hexdump, stat, loadm, savem, exec, mkdir, mv, cp, rm,
    diskread, and diskwrite.

* Expand debug mode as needed.
    |debug[,0|1] now controls diskread's OPEN/HDR/DONE/REM diagnostics. Add
    more request/response diagnostics only where they help diagnose real issues.
