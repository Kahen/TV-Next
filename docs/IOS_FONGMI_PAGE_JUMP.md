# Native FongMi page jump

iPhone/iPad home, category and single-provider search pages now expose an explicit page number field. The field follows the last successful server response. Invalid or unchanged input cannot issue a request.

Only ASCII decimal digits are accepted after trimming outer whitespace; valid page numbers are 1 through 10,000. The existing browse API is used, preserving the selected provider, category and applied filters. Failed requests leave the current results visible. The Next button stops at page 10,000.

This requests only the selected page; external providers may not support arbitrary offsets. XCTest covers positive boundaries and negative malformed, Unicode, zero, overflow and out-of-range values. Full Xcode integration remains unverified.
