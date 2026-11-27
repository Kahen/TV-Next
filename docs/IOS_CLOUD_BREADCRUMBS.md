# iOS AList/OpenList directory breadcrumbs

The native cloud browser now shows tappable ancestor directories for the current
AList/OpenList listing. Selecting an ancestor invokes the existing `cloud/list`
request with the current in-memory credentials and resets pagination to page 1.
The active directory is displayed but not tappable. This does not add SMB support,
OAuth, or a new cloud service protocol.

`NativeCloudBreadcrumbs.make` accepts only absolute slash-delimited paths.
Relative paths, empty interior/trailing components, dot/dot-dot traversal,
backslashes, Unicode control and format characters fall back to a root-only
breadcrumb. It preserves valid Unicode, case and spaces. The existing server
still owns authorization and canonical path enforcement; this is a UI navigation
guard, not a replacement for server-side path validation.

Unit coverage: root, nested Unicode, exact prefix paths, valid whitespace,
relative/UNC paths, traversal, duplicate/trailing separators and invisible
characters. iPhone/iPad XCTest and full CI must pass before merge; no real cloud
account or device acceptance is claimed.
