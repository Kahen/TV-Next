# iOS SMB bounded read-range model

This change introduces a pure Swift read-only SMB byte-range validator for the future direct SMB transport. It is not a network SMB client and does not enable directory listing or AVPlayer streaming.

A request is accepted only when the remote file size is positive, the offset is nonnegative and inside the file, the requested length is 1 through 1 MiB, and the entire range fits the file. Subtraction-based checks avoid signed offset-plus-length overflow.

The future transport must obtain a trustworthy file size from an authenticated SMB handle, enforce an aggregate transfer budget, support cancellation and reconnect, and avoid exposing credentials in URLs/logs. The validator does not authorize access or protect against a remote file changing size between reads.

Tests: `NativeSMBReadRangeTests` covers initial/final bytes, empty files, negative offsets, EOF, oversized requests, and integer boundaries. Run with the native iOS XCTest target on macOS/Xcode.
