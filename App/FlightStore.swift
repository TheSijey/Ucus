import Foundation
import SwiftUI

struct PlannedFlight: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date      // UTC günün başlangıcı (roster'daki tarih)
    var flight: String  // "TK1751" (ilk bacak)
    var kind: TripKind? = nil          // nil: eski kayıt, dönüş otomatik
    var legs: [PlannedLeg]? = nil      // ilk bacaktan sonrakiler
    var airports: [String]? = nil      // ekleme ekranında bulunan meydanlar (Meydanlar sekmesi için)

    /// Yüklemeye gidecek bacak numaraları: nil = otomatik dönüş tahmini.
    var legNumbers: [String]? {
        guard kind != nil else { return nil }
        return (legs ?? []).map(\.flight).filter { !$0.isEmpty }
    }

    /// "TK1751 · TK1752 · TK2010"
    var summary: String { ([flight] + (legs ?? []).map(\.flight)).joined(separator: " · ") }
}

enum TripKind: String, Codable, CaseIterable {
    case single, turn
}

struct PlannedLeg: Codable, Hashable, Identifiable {
    var id = UUID()
    var flight: String
    var dayOffset: Int = 0
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
    func add(date: Date, flight raw: String, kind: TripKind? = nil, legs: [PlannedLeg]? = nil, airports: [String]? = nil) {
        let flight = Self.normalizeFlight(raw)
        guard !flight.isEmpty else { return }
        let day = UTC.startOfDay(date)
        let cleanLegs = legs?.map { PlannedLeg(id: $0.id, flight: Self.normalizeFlight($0.flight), dayOffset: $0.dayOffset) }.filter { !$0.flight.isEmpty }
        if let i = flights.firstIndex(where: { $0.date == day && $0.flight == flight }) {
            flights[i].kind = kind
            flights[i].legs = cleanLegs
            flights[i].airports = airports
        } else {
            flights.append(PlannedFlight(date: day, flight: flight, kind: kind, legs: cleanLegs, airports: airports))
        }
        save()
    }

    func update(_ f: PlannedFlight) {
        guard let i = flights.firstIndex(where: { $0.id == f.id }) else { return }
        var g = f
        g.flight = Self.normalizeFlight(f.flight)
        g.date = UTC.startOfDay(f.date)
        g.legs = f.legs?.map { PlannedLeg(id: $0.id, flight: Self.normalizeFlight($0.flight), dayOffset: $0.dayOffset) }.filter { !$0.flight.isEmpty }
        flights[i] = g
        save()
    }

    func delete(_ flight: PlannedFlight) {
        flights.removeAll { $0.id == flight.id }
        save()
    }

    private static let startedKey = "startedPlannedFlight"   // [id, hideAt]

    /// Ada'ya eklenen planlı uçuşu hatırla; tur bitince listeden düşer.
    static func markStarted(_ flight: PlannedFlight, until end: Date) {
        UserDefaults.standard.set([flight.id.uuidString, end.timeIntervalSince1970], forKey: startedKey)
    }

    /// - Uçuş günü (UTC) bittikten sonra ertesi sabah 09:00'a (TR, 06:00 UTC) kadar kalır, sonra silinir.
    /// - Ada'ya eklenen uçuş tur bitince silinir.
    func prune() {
        let now = Date()
        flights.removeAll { $0.date.addingTimeInterval(30 * 3600) <= now }   // gün sonu + 6 saat
        if let arr = UserDefaults.standard.array(forKey: Self.startedKey), arr.count == 2,
           let idString = arr[0] as? String, let hide = arr[1] as? Double,
           Date(timeIntervalSince1970: hide) <= now {
            flights.removeAll { $0.id.uuidString == idString }
            UserDefaults.standard.removeObject(forKey: Self.startedKey)
        }
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
        WidgetSync.push()
    }
}

enum AppSettings {
    static let leaveMinutesKey = "leaveMinutes"
    /// İmzadan kaç dk önce evden çıkılıyor (0 = kapalı). Varsayılan 60.
    static var leaveMinutes: Int {
        UserDefaults.standard.object(forKey: leaveMinutesKey) as? Int ?? 60
    }

    static let activityLeadKey = "activityLeadHours"
    /// Kilit ekranı ve Ada'ya imzadan kaç saat önce eklensin (0 = CDM'de bulununca hemen).
    static var activityLeadHours: Int {
        UserDefaults.standard.object(forKey: activityLeadKey) as? Int ?? 0
    }

    static let hotelRemindKey = "hotelRemindMinutes"
    /// Otelden çıkıştan kaç dk önce hatırlatılsın. Varsayılan 15.
    static var hotelRemindMinutes: Int {
        UserDefaults.standard.object(forKey: hotelRemindKey) as? Int ?? 15
    }
}
