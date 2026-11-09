import SwiftUI

@main
struct UcusApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await LiveActivityManager.endExpired() }
            }
        }
        .backgroundTask(.appRefresh(LiveActivityManager.cleanupTaskID)) {
            await LiveActivityManager.endExpired()
        }
    }
}
