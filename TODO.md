* Improve cp so it can copy into a folder
    cp foo bar when bar is a folder says bar exists
    no need to go as far as recursive copy though
* Tighten AMSDOS header detection in |stat so random payload bytes are less
    likely to be reported as a valid header.
* Keep |diskread header behaviour explicit once header-preserving reads are in:
    default should preserve the 128-byte AMSDOS header, with a payload-only mode
    if we still want one.
