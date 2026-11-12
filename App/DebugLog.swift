import ActivityKit
import Foundation

/// Son 60 olayı saklayan küçük kayıt (Ayarlar > Tanılama).
enum DebugLog {
    private static let key = "debugLog"

    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ text: String) {
        let stamp = Date().formatted(.dateTime.day().month(.abbreviated).hour().minute().second())
        var l = lines
        l.insert("\(stamp)  \(text)", at: 0)
        UserDefaults.standard.set(Array(l.prefix(60)), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Canlı Etkinliğin durum değişikliklerini (bitti, kaldırıldı…) kaydeder.
@MainActor
enum ActivityObserver {
    private static var watched: Set<String> = []

    static func watchAll() {
        for a in Activity<FlightAttributes>.activities { watch(a) }
    }

    static func watch(_ activity: Activity<FlightAttributes>) {
        guard !watched.contains(activity.id) else { return }
        watched.insert(activity.id)
        let flight = activity.content.state.flight
        Task {
            for await st in activity.activityStateUpdates {
                DebugLog.add("Etkinlik \(flight): durum → \(String(describing: st))")
            }
        }
    }
}
