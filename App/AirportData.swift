import Foundation
import SwiftUI
import UserNotifications

// MARK: - Modeller

/// Bir uçuştan sonra girilen kısa kayıt (varış ya da kalkış). İstatistikler bunlardan çıkar.
struct FlightRecord: Identifiable, Codable, Hashable {
    enum Phase: String, Codable, CaseIterable { case arrival, departure }

    var id = UUID()
    var icao: String
    var phase: Phase
    var date = Date()
    var flight: String = ""
    var aircraftType: String = ""
    var runway: String = ""
    var procedure: String = ""     // STAR (varış) / SID (kalkış)
    var approach: String = ""      // ILS, RNP, Visual, Diğer (varış)
    var taxi: String = ""
    var stand: String = ""
    var windDir: Int? = nil
    var windSpeed: Int? = nil
    var apu: String = ""           // "gate'ten sonra 5 dk" gibi
    var author: String = Identity.id
}

/// Meydan notu: operasyon (hotspot, ATC ...) ya da layover (otel, servis yeri ...).
struct AirportNote: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        // Operasyon / yorumlar
        case hotspot, atc, crewBus, handling, apu, noise, other
        // Layover
        case hotel, pickup, laundry, breakfast, place, safety, practical
        var id: String { rawValue }

        var isLayover: Bool { [.hotel, .pickup, .laundry, .breakfast, .place, .safety, .practical].contains(self) }
        static var ops: [Kind] { allCases.filter { !$0.isLayover } }
        static var layover: [Kind] { allCases.filter { $0.isLayover } }

        var title: String {
            switch self {
            case .hotspot: "Hotspot"
            case .atc: L("ATC", "ATC")
            case .crewBus: "Crew bus"
            case .handling: "Handling"
            case .apu: "APU"
            case .noise: L("Gürültü", "Noise")
            case .other: L("Diğer", "Other")
            case .hotel: L("Otel", "Hotel")
            case .pickup: L("Servis yeri", "Pickup point")
            case .laundry: L("Laundry", "Laundry")
            case .breakfast: L("Kahvaltı", "Breakfast")
            case .place: L("Mekân önerisi", "Place tip")
            case .safety: L("Bölge notu", "Area note")
            case .practical: L("Pratik bilgi", "Practical")
            }
        }

        var color: Color {
            switch self {
            case .hotspot, .safety: Color(red: 1, green: 0.62, blue: 0.41)
            case .apu, .noise: Palette.signOn
            default: Color(red: 0.56, green: 0.78, blue: 1)
            }
        }
    }

    var id = UUID()
    var icao: String
    var kind: Kind
    var text: String
    var placeCategory: String = ""     // mekân: Kahve, Yemek, Market, Koşu ...
    var createdAt = Date()
    var author: String = Identity.id
}

/// Bir nota "hâlâ geçerli" / "değişti" oyu.
struct NoteVote: Identifiable, Codable, Hashable {
    var id = UUID()
    var icao: String
    var noteID: UUID
    var valid: Bool
    var date = Date()
    var author: String = Identity.id
}

/// Otel puanı (1–5).
struct HotelRating: Identifiable, Codable, Hashable {
    var id = UUID()
    var icao: String
    var gym = 0
    var wifi = 0
    var dark = 0
    var quiet = 0
    var date = Date()
    var author: String = Identity.id
}

/// Cihaza özel, isimsiz kullanıcı kimliği (oy ve kayıtları ayırmak için).
enum Identity {
    static var id: String {
        let k = "anonAuthorID"
        if let v = UserDefaults.standard.string(forKey: k) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: k)
        return v
    }
}

// MARK: - Depo

/// Meydan verileri: kendi kayıtların (cihazda) + ortak veriler (CloudKit açıksa).
@MainActor
final class AirportStore: ObservableObject {
    static let shared = AirportStore()

    struct DataSet: Codable {
        var records: [FlightRecord] = []
        var notes: [AirportNote] = []
        var votes: [NoteVote] = []
        var ratings: [HotelRating] = []
    }

    @Published private(set) var local = DataSet()
    @Published private(set) var cloud: [String: DataSet] = [:]     // icao → ortak veri
    @Published var cloudStatus: String?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("airports.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let b = try? JSONDecoder().decode(DataSet.self, from: data) {
            local = b
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(local) { try? data.write(to: fileURL, options: .atomic) }
    }

    // Birleşik görünüm (yerel + ortak, aynı kimlik bir kez)
    private func merged<T: Identifiable>(_ a: [T], _ b: [T]) -> [T] where T.ID == UUID {
        var seen = Set<UUID>()
        return (a + b).filter { seen.insert($0.id).inserted }
    }

    func records(_ icao: String) -> [FlightRecord] {
        merged(local.records.filter { $0.icao == icao }, cloud[icao]?.records ?? [])
    }
    func notes(_ icao: String) -> [AirportNote] {
        merged(local.notes.filter { $0.icao == icao }, cloud[icao]?.notes ?? [])
    }
    func votes(_ icao: String) -> [NoteVote] {
        merged(local.votes.filter { $0.icao == icao }, cloud[icao]?.votes ?? [])
    }
    func ratings(_ icao: String) -> [HotelRating] {
        merged(local.ratings.filter { $0.icao == icao }, cloud[icao]?.ratings ?? [])
    }

    /// Kayıt ya da notu olan meydanlar (son kullanılan önce).
    var knownAirports: [String] {
        var last: [String: Date] = [:]
        for r in local.records { last[r.icao] = max(last[r.icao] ?? .distantPast, r.date) }
        for n in local.notes { last[n.icao] = max(last[n.icao] ?? .distantPast, n.createdAt) }
        for (k, b) in cloud where !(b.records.isEmpty && b.notes.isEmpty) { last[k] = last[k] ?? .distantPast }
        return last.sorted { $0.value > $1.value }.map(\.key)
    }

    func add(_ r: FlightRecord) {
        local.records.append(r); persist()
        Task { await CloudSync.save(r, type: "record", icao: r.icao) }
    }
    func add(_ n: AirportNote) {
        local.notes.append(n); persist()
        Task { await CloudSync.save(n, type: "note", icao: n.icao) }
    }
    func add(_ r: HotelRating) {
        local.ratings.removeAll { $0.icao == r.icao && $0.author == r.author }
        local.ratings.append(r); persist()
        Task { await CloudSync.save(r, type: "rating", icao: r.icao) }
    }
    func vote(_ note: AirportNote, valid: Bool) {
        local.votes.removeAll { $0.noteID == note.id && $0.author == Identity.id }
        let v = NoteVote(icao: note.icao, noteID: note.id, valid: valid)
        local.votes.append(v); persist()
        Task { await CloudSync.save(v, type: "vote", icao: v.icao) }
    }
    func delete(_ note: AirportNote) {
        local.notes.removeAll { $0.id == note.id }; persist()
        Task { await CloudSync.delete(note.id) }
    }

    /// Ortak verileri yenile.
    func load(_ icao: String) async {
        guard CloudSync.enabled else { return }
        do {
            cloud[icao] = try await CloudSync.fetch(icao: icao)
            cloudStatus = nil
        } catch {
            cloudStatus = L("Ortak veriler alınamadı: \(error.localizedDescription)", "Couldn't load shared data: \(error.localizedDescription)")
        }
    }
}

// MARK: - İstatistik

struct Share: Identifiable, Hashable {
    var id: String { value }
    let value: String
    let count: Int
    let percent: Int
}

enum AirportStats {
    /// Değerlerin dağılımı (boşlar hariç), en sık önce.
    static func distribution(_ values: [String], limit: Int = 4) -> [Share] {
        let v = values.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
        guard !v.isEmpty else { return [] }
        let counts = Dictionary(v.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { Share(value: $0.key, count: $0.value, percent: Int((Double($0.value) / Double(v.count) * 100).rounded())) }
    }

    /// "C214" → "C", "T2B12" → "T2B": standın bölgesi (ilk rakam dizisine kadar, en az bir harf).
    static func standArea(_ stand: String) -> String {
        let s = stand.uppercased()
        guard let first = s.firstIndex(where: \.isNumber) else { return s }
        let head = String(s[..<first])
        return head.isEmpty ? String(s.prefix(1)) : head
    }

    /// Rüzgâr yönü benzer mi (±60°)?
    static func similarWind(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return false }
        let d = abs(a - b) % 360
        return min(d, 360 - d) <= 60
    }
}

// MARK: - Uçuş sonrası kayıt hatırlatması

extension NotificationManager {
    static func recordID(_ s: FlightAttributes.ContentState) -> String { "record-" + BriefingStore.key(for: s) }

    /// İnişten 15 dk sonra "kısa kayıt" bildirimi.
    static func scheduleRecord(_ s: FlightAttributes.ContentState) async {
        guard let arr = s.turn?.outboundArrival, let dest = FlightHelpers.destICAO(s) else { return }
        let fire = arr.addingTimeInterval(15 * 60)
        guard fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = L("\(s.flight) indi · \(dest)", "\(s.flight) landed · \(dest)")
        content.body = L("20 saniyelik kayıt: pist, stand, taksi. Sonraki ekiplerin işine yarar.", "20-second log: runway, stand, taxi. It helps the next crews.")
        content.userInfo = ["openRecord": dest]
        content.interruptionLevel = .passive
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: recordID(s), content: content,
                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

extension Notification.Name {
    static let openFlightRecord = Notification.Name("openFlightRecord")
}
