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
        content.title = "\(flight) – Çıkma vakti"
        content.body = "İmzaya \(Display.minutes(minutesBeforeSignOn))."
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
        content.title = "Uçuş – deneme"
        content.body = "Çıkış bildirimi böyle gelecek."
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
