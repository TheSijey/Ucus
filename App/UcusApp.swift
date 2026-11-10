import SwiftUI

@main
struct UcusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await LiveActivityManager.refreshPhase() }
            }
        }
        .backgroundTask(.appRefresh(LiveActivityManager.wakeTaskID)) {
            await LiveActivityManager.refreshPhase()
        }
    }
}
