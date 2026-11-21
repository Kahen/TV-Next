# iOS cloud listing navigation

The native AList/OpenList browser constructs child paths only from absolute server directory paths and single-component entry names. It rejects empty, dot/dot-dot, slash/backslash, control and Unicode format-character names. Parent traversal uses the current path components and stops at `/`. Valid Unicode and spaces remain supported.

This guards against malformed or hostile listing names being interpreted as a different directory or file request. It does not validate the remote server's authorization, prevent server-side symlink traversal, or add SMB support.

`MediaLibraryTests` contains positive Unicode/root cases and negative traversal/control cases. Xcode iPhone/iPad XCTest and final-head integration remain unverified until CI runs. No external cloud credentials or media are bundled.
