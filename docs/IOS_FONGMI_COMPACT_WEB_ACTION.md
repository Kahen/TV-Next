# Native FongMi compact web action

Some type-4 provider actions return `{"web":"https://login.example.org/verify"}` rather than the nested `{"web":{"url":"https://login.example.org/verify","mode":"browser"}}` shape. The native action decoder now accepts both. The SwiftUI action view continues to offer a **user-initiated** external-browser link; no page opens automatically.

Both shapes use the same URL checks: only HTTP(S), a nonempty host, no URL userinfo, no ASCII control characters or backslashes, and a maximum 4096 UTF-8 bytes. Object-only `mode=view` and cookie requests still warn that embedded WebView/cookie collection are not implemented. No credentials or cookies are captured, forwarded or persisted.

Regression cases in `apps/ios/tests/ActionSmoke.swift` cover compact and object forms, message preservation, unsupported schemes, userinfo, backslashes and control characters. Run the existing ActionSmoke harness and iOS XCTest/CI before merging. This is a compatibility increment, not a complete interactive form or provider-login implementation.
