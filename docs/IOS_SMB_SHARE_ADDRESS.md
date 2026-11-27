# Native SMB share-address parsing

The native iOS SMB work now has a credential-free share-address model
(`NativeSMBShareAddress`). It recognizes `smb://host/share/path` and an
optional explicit TCP port. Percent-encoded Unicode and spaces in share/path
components are decoded once. Credentials, query/fragment, empty components,
traversal, control characters and ambiguous encoded separators are rejected.

This is **not** a direct SMB client. No socket, SMB negotiation, authentication,
directory listing or streaming is implemented by this increment. It does not
replace the existing Files-provider SMB import workflow. Future native browsing
must pass parsed components to an authenticated SMB transport, enforce share-root
containment at the transport layer and avoid storing passwords in URL strings.

Tests: `NativeSMBShareAddressTests` covers valid Unicode and nested paths,
credentials, unsupported schemes, traversal and encoded separators. Run through
the iOS XCTest target on macOS/Xcode; simulator and transport integration remain
unverified until the relevant checks run.
