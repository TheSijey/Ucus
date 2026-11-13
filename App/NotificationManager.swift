import Foundation
import UIKit
import UserNotifications

enum NotificationManager {
    static let leaveID = "leave-home"
    static let chime = UNNotificationSound(named: UNNotificationSoundName("chime.wav"))

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Evden çıkış bildirimi (uçak chime sesiyle).
    static func scheduleLeave(flight: String, at date: Date, minutesBeforeSignOn: Int) async {
        cancelLeave()
        guard date > Date() else { return }
        await requestAuthorization()

        let content = UNMutableNotificationContent()
        content.title = L("\(flight) – Çıkma vakti", "\(flight) – Time to leave")
        content.body = L("İmzaya \(Display.minutes(minutesBeforeSignOn)).", "\(Display.minutes(minutesBeforeSignOn)) to sign-on.")
        content.sound = chime
        content.interruptionLevel = .active

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: leaveID, content: content, trigger: trigger))
    }

    static func cancelLeave() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [leaveID])
    }

    /// Ayarlardaki "Sesi dene" için 3 sn sonra deneme bildirimi.
    static func test() async {
        await requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = L("Uçuş – deneme", "Uçuş – test")
        content.body = L("Çıkış bildirimi böyle gelecek.", "This is how the leave alert will look.")
        content.sound = chime
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "test-\(UUID())", content: content, trigger: trigger))
    }
}

/// Uygulama açıkken de bildirimi göster; bildirime dokununca Ada'yı imza sayacına geçir.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await LiveActivityManager.refreshPhase()
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await LiveActivityManager.refreshPhase()
    }
}
