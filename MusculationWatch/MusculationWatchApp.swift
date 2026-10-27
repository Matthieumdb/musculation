import SwiftUI

@main
struct MusculationWatchApp: App {
    @State private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
        }
    }
}
