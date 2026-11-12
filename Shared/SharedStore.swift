import Foundation

/// Uygulama ile widget arasında ortak veri (App Group).
enum SharedStore {
    static let group = "group.com.cengiz.ucus"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    struct Active: Codable, Hashable {
        var flight: String
        var registration: String
        var stand: String
        var gate: String
        var destination: String
        var signOn: Date
        var leaveAt: Date?
        var hideAt: Date
    }

    struct Planned: Codable, Hashable {
        var flight: String
        var date: Date   // UTC gün başlangıcı
    }

    private static let activeKey = "widget.active"
    private static let plannedKey = "widget.planned"

    static var active: Active? {
        get { defaults.data(forKey: activeKey).flatMap { try? JSONDecoder().decode(Active.self, from: $0) } }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: activeKey) }
            else { defaults.removeObject(forKey: activeKey) }
        }
    }

    static var planned: [Planned] {
        get { defaults.data(forKey: plannedKey).flatMap { try? JSONDecoder().decode([Planned].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: plannedKey) }
    }
}
