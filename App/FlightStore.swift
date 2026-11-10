import Foundation
import SwiftUI

struct PlannedFlight: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date      // günün başlangıcı (yerel)
    var flight: String  // "TK1751"
}

/// Kullanıcının elle girdiği uçuşlar. Telefonda saklanır, geçmiş günler kendiliğinden silinir.
@MainActor
final class FlightStore: ObservableObject {
    @Published private(set) var flights: [PlannedFlight] = []
    private let key = "plannedFlights"

    init() {
        load()
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

    func add(date: Date, flight raw: String) {
        let flight = Self.normalizeFlight(raw)
        guard !flight.isEmpty else { return }
        let day = Calendar.current.startOfDay(for: date)
        guard !flights.contains(where: { $0.date == day && $0.flight == flight }) else { return }
        flights.append(PlannedFlight(date: day, flight: flight))
        save()
    }

    func delete(_ flight: PlannedFlight) {
        flights.removeAll { $0.id == flight.id }
        save()
    }

    func prune() {
        let today = Calendar.current.startOfDay(for: Date())
        flights.removeAll { $0.date < today }
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
