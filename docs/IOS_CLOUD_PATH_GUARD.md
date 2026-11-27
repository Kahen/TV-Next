# iOS cloud path component guard

AList/OpenList folder entries are now joined using `NativeCloudPath.child` instead of raw string concatenation. Valid Unicode filenames and nested paths are retained. Empty names, dot traversal, path separators and control/line separators are rejected before sending `cloud/list` or `cloud/play` requests. Parent navigation is root-bounded.

This is a client-side path guard, not SMB2/3 support or a substitute for server-side authorization/path validation. Tests: `NativeCloudPathTests` (positive Unicode/nested paths and negative traversal/separator cases). Xcode XCTest and device integration are not verified by this change.
