import Foundation

/// Dış meydan kalkışında elle girilen bilgiler: imza, otelden çıkış, stand.
/// Uçuş + kalkış günü (UTC) ile saklanır; yenilemede AeroDataBox verisinin üstüne yazılır.
enum ManualTimes {
    struct Entry: Codable, Equatable {
        var signOn: Date?
        var pickup: Date?
        var stand: String?
    }

    private static let storeKey = "manualTimes"

    private static var store: [String: Entry] {
        get {
            guard let d = UserDefaults.standard.data(forKey: storeKey),
                  let s = try? JSONDecoder().decode([String: Entry].self, from: d) else { return [:] }
            return s
        }
        set {
            // 3 günden eski kayıtları at
            let fresh = newValue.filter { ($0.value.signOn ?? $0.value.pickup ?? Date()) > Date().addingTimeInterval(-3 * 86_400) }
            UserDefaults.standard.set(try? JSONEncoder().encode(fresh), forKey: storeKey)
        }
    }

    static func key(_ s: FlightAttributes.ContentState) -> String {
        let day = (s.eobt ?? s.signOn).formatted(.iso8601.year().month().day())
        return "\(s.flight)|\(day)"
    }

    static func entry(for s: FlightAttributes.ContentState) -> Entry { store[key(s)] ?? Entry() }

    static func save(_ e: Entry, for s: FlightAttributes.ContentState) {
        var st = store
        st[key(s)] = e
        store = st
    }

    /// Elle girilenleri duruma uygular. İmza girilmediyse tahmin (kalkış − 1 sa) kalır.
    static func apply(_ input: FlightAttributes.ContentState) -> FlightAttributes.ContentState {
        var s = input
        let e = entry(for: s)
        if let so = e.signOn {
            s.signOn = so
            s.signOnManual = true
        } else {
            s.signOnManual = false
        }
        s.pickupAt = e.pickup
        if let st = e.stand, !st.isEmpty { s.stand = st }
        return s
    }
}
