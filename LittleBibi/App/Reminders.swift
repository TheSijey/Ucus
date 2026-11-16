import Foundation
import UserNotifications

/// Kontrol, aşı ve D vitamini hatırlatmaları. Ayarlar her telefonda ayrıdır.
@MainActor
enum Reminders {
    static let scheduleKey = "remindSchedule"
    static let vitaminKey = "remindVitamin"
    static let vitaminMinutesKey = "vitaminMinutes"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Bekleyen hatırlatmaları güncel verilere göre yeniden kurar.
    static func refresh(_ store: Store) {
        let defaults = UserDefaults.standard
        let cal = Calendar.current
        let now = Date()
        var requests: [UNNotificationRequest] = []

        func add(_ id: String, _ title: String, _ body: String, at date: Date) {
            guard date > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            requests.append(UNNotificationRequest(identifier: "lb-" + id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        if let birth = store.profile.birthDate {
            let name = store.profile.babyName.isEmpty ? "Bebeğiniz" : store.profile.babyName

            if defaults.bool(forKey: scheduleKey) {
                for item in Schedule.items where !store.isDone(item.key) {
                    let due = item.due(birth: birth)
                    let dayBefore = cal.date(byAdding: .day, value: -1, to: due) ?? due
                    if let t = cal.date(bySettingHour: 10, minute: 0, second: 0, of: dayBefore), t > now {
                        add("s-" + item.key, "Yarın: \(item.title)", "\(name) için \(item.detail)", at: t)
                    } else if let t = cal.date(bySettingHour: 9, minute: 0, second: 0, of: due) {
                        add("s-" + item.key, "Bugün: \(item.title)", "\(name) için \(item.detail)", at: t)
                    }
                }
            }

            let ageDays = cal.dateComponents([.day], from: birth, to: now).day ?? 0
            if defaults.bool(forKey: vitaminKey), ageDays < 366 {
                let minutes = defaults.object(forKey: vitaminMinutesKey) as? Int ?? 9 * 60
                for offset in 0..<14 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)), day >= cal.startOfDay(for: birth) else { continue }
                    if store.vitaminMark(on: day) != nil { continue }
                    if let t = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) {
                        add("v-" + VitaminMark.dayKey(day), "D vitamini zamanı", "\(name) bugünkü D vitaminini aldı mı?", at: t)
                    }
                }
            }
        }

        let center = UNUserNotificationCenter.current()
        let pending = requests
        center.getPendingNotificationRequests { existing in
            let ours = existing.map(\.identifier).filter { $0.hasPrefix("lb-") }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for request in pending {
                center.add(request)
            }
        }
    }
}
