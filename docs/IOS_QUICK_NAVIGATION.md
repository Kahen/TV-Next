# Native iPhone/iPad quick navigation

TV-Next is a SwiftUI iPhone/iPad application with a single vertically scrolling
content screen and a top-right **功能导航** menu. For physical-device acceptance,
the menu now includes **TVBox 订阅**, **网盘文件**, **直播节目表**,
**家庭服务器**, and **弹幕设置**, in addition to player, URL entry,
local media/captions, playlist import, JSON configuration and media library.
Each entry scrolls to the actual production view without replacing its state.

## Physical iPhone/iPad workflow

1. Start with **功能导航 → 家庭服务器** and configure your own reachable
   HTTPS API, if using server-backed FongMi HTTP providers. The development
   default `http://localhost:8080` refers to the *phone itself*, not your
   NAS; use the actual device-reachable URL instead.
2. In **TVBox 订阅**, paste an authorized configuration or enter its URL, then
   load it. Type 0/1/2/4 HTTP sites support the documented browsing subset
   and direct compatible media; type 3 Spider JAR sites are still unsupported.
3. Select a site, category, movie and episode. When the home server is signed
   in, header-dependent HTTP/HLS streams may use its authenticated media relay.
4. Use **网盘文件** for your own AList/OpenList service; provide its API token
   only when required. The native app does not automatically log in to
   arbitrary Aliyun/Quark/115 Spider sources.
5. Visit **直播节目表** for imported XMLTV or account-scoped subscribed
   guides. **弹幕设置** applies to the native overlay, not system PiP.

Native XCTest/XCUI covers the navigation menu and code-level feature
contracts in the simulator. Physical H.264/H.265, Files provider permissions,
PiP/background behavior, VoiceOver, networks and extended playback still need
manual device evidence in #38. This navigation improvement does not create an
installable signed IPA. Use Xcode signing with your own Apple team for a
physical-device development build; Apple TestFlight/App Store distribution
needs separate signing/provisioning and policy verification.
