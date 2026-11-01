import SwiftUI

@main
struct TVNextApp: App {
    init() {
        // The previous process cannot have an active Files import or player.
        // Reclaim only app-generated, nonpersistent staging copies.
        LocalMediaStager.purgeAbandonedImports()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
