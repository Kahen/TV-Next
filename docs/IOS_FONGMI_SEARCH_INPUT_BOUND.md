# Native FongMi search input boundary

The iPhone/iPad cross-provider search submits only nonempty, trimmed search terms of at most 256 Swift Characters. Cc/Cf Unicode scalars and U+2028/U+2029 are rejected; meaningful Chinese text and internal spaces remain unchanged. This is a local input bound, not provider-specific compatibility or Spider support.

The single-site search buttons share the input validation gate. Cross-provider search also validates at the execution boundary and displays an error instead of dispatching an invalid request. Failed-provider retry uses the original submitted query snapshot.

XCTest: `NativeFongMiSearchInputTests` covers valid Unicode, maximum boundary, empty, overlong, NUL, bidi override and line separator. Full iOS simulator/CI integration remains unverified until run on Xcode.
