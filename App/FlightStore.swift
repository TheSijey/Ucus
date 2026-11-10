import Foundation
import SwiftUI

struct PlannedFlight: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date      // UTC günün başlangıcı (roster'daki tarih)
    var flight: String  // "TK1751"
}

/// Roster UTC olduğu için uçuş tarihleri UTC tutulur ve gösterilir.
enum UTC {
    static let zone = TimeZone(identifier: "UTC")!
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }
    static func startOfDay(_ d: Date) -> Date { calendar.startOfDay(for: d) }
}

/// Kullanıcının elle girdiği uçuşlar. Telefonda saklanır, geçmiş günler kendiliğinden silinir.
@MainActor
final class FlightStore: ObservableObject {
    @Published private(set) var flights: [PlannedFlight] = []
    private let key = "plannedFlights"
    private let utcMigratedKey = "plannedFlightsUTC"

    init() {
        load()
        migrateToUTC()
        prune()
    }

    var upcoming: [PlannedFlight] {
        flights.sorted { ($0.date, $0.flight) < ($1.date, $1.flight) }
    }

    /// "1751" / "tk 1751" -> "TK1751"
    static func normalizeFlight(_ raw: String) -> String {
        let s = raw.uppercased().replacingOccurrences(of: " ", with: "")
        if s.range(of: #"^\d"#, options: .regularExpression) != nil { return "TK" + s }
        return s
    }

    /// `date`: UTC takvimde seçilmiş gün.
    func add(date: Date, flight raw: String) {
        let flight = Self.normalizeFlight(raw)
        guard !flight.isEmpty else { return }
        let day = UTC.startOfDay(date)
        guard !flights.contains(where: { $0.date == day && $0.flight == flight }) else { return }
        flights.append(PlannedFlight(date: day, flight: flight))
        save()
    }

    func delete(_ flight: PlannedFlight) {
        flights.removeAll { $0.id == flight.id }
        save()
    }

    /// Dünden (UTC) eski uçuşları siler; gece yarısını geçen uçuşlar için dün de kalır.
    func prune() {
        let cal = UTC.calendar
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        flights.removeAll { $0.date < yesterday }
        save()
    }

    /// Eski sürümde yerel gün başlangıcı saklanıyordu; aynı gün/ay/yılı UTC'ye taşı.
    private func migrateToUTC() {
        guard !UserDefaults.standard.bool(forKey: utcMigratedKey) else { return }
        let local = Calendar.current
        flights = flights.map { f in
            var f = f
            let comps = local.dateComponents([.year, .month, .day], from: f.date)
            if let d = UTC.calendar.date(from: comps) { f.date = d }
            return f
        }
        UserDefaults.standard.set(true, forKey: utcMigratedKey)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([PlannedFlight].self, from: data) else { return }
        flights = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(flights) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum AppSettings {
    static let leaveMinutesKey = "leaveMinutes"
    /// İmzadan kaç dk önce evden çıkılıyor (0 = kapalı). Varsayılan 60.
    static var leaveMinutes: Int {
        UserDefaults.standard.object(forKey: leaveMinutesKey) as? Int ?? 60
    }
}
