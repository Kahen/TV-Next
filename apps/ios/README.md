# TV-Next for iPhone and iPad

Universal SwiftUI native client with AVKit/AVPlayer. Development requires macOS + Xcode 16+ and XcodeGen.

1. Install XcodeGen (for example, brew install xcodegen).
2. In apps/ios run xcodegen generate.
3. Open TVNext.xcodeproj in Xcode and run the TVNext scheme on an iOS 17+ simulator.
4. For M3U import, run the API locally and use the default http://localhost:8080 in the simulator. On a physical device, use an appropriately secured reachable API endpoint, preferably HTTPS.
5. For playback, provide an authorized MP4 or HLS URL; AVPlayer codec and ATS limitations apply.

This is an early native UI, not an iOS execution environment for Android JAR, AAR or Spider plugins. The full features are scoped in docs/ROADMAP.md.
