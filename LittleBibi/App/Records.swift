import Foundation

/// Aileyle eşitlenen her kayıt türünün ortak yanı.
protocol SyncRecord: Codable {
    var recordName: String { get }
    var modified: Date { get set }
    var deleted: Bool { get set }
    var author: String { get set }
}

// MARK: Takı defteri

enum GiftKind: String, Codable, CaseIterable, Identifiable {
    case gold, money, present
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gold: return "Altın"
        case .money: return "Para"
        case .present: return "Hediye"
        }
    }
    var symbol: String {
        switch self {
        case .gold: return "circle.hexagongrid.fill"
        case .money: return "banknote.fill"
        case .present: return "gift.fill"
        }
    }
}

struct Gift: SyncRecord, Identifiable, Equatable {
    var id = UUID()
    var giver: String = ""
    var relation: String = ""
    var kind: GiftKind = .gold
    /// "Çeyrek altın", "Zarf", "Battaniye" gibi.
    var what: String = ""
    var count: Int = 1
    var date: Date = Date()
    var thanked: Bool = false
    var note: String = ""
    var author: String = ""
    var modified: Date = Date()
    var deleted: Bool = false

    var recordName: String { "g-" + id.uuidString }

    var summary: String {
        let name = what.isEmpty ? kind.title : what
        return count > 1 ? "\(count) × \(name)" : name
    }
}

// MARK: Doktora sorulacaklar

struct Question: SyncRecord, Identifiable, Equatable {
    var id = UUID()
    var text: String = ""
    var created: Date = Date()
    var answered: Bool = false
    var answer: String = ""
    var answeredAt: Date? = nil
    var author: String = ""
    var modified: Date = Date()
    var deleted: Bool = false

    var recordName: String { "q-" + id.uuidString }
}

// MARK: Gelişim

struct Measurement: SyncRecord, Identifiable, Equatable {
    var id = UUID()
    var date: Date = Date()
    var weightGrams: Int? = nil
    var heightCm: Double? = nil
    var headCm: Double? = nil
    var note: String = ""
    var author: String = ""
    var modified: Date = Date()
    var deleted: Bool = false

    var recordName: String { "m-" + id.uuidString }

    var summary: String {
        var parts: [String] = []
        if let w = weightGrams { parts.append(Fmt.kg(w)) }
        if let h = heightCm { parts.append("\(Fmt.decimal(h)) cm") }
        if let c = headCm { parts.append("baş \(Fmt.decimal(c)) cm") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Takvim işaretleri ve D vitamini

/// Takvimdeki bir kontrolün ya da aşının yapıldığını gösterir.
struct ScheduleMark: SyncRecord, Identifiable, Equatable {
    var key: String
    var doneAt: Date? = nil
    var author: String = ""
    var modified: Date = Date()
    var deleted: Bool = false

    var id: String { key }
    var recordName: String { "s-" + key }
}

/// Bir günün D vitamini verildi işareti. Gün başına tek kayıt.
struct VitaminMark: SyncRecord, Identifiable, Equatable {
    var day: String
    var givenAt: Date = Date()
    var author: String = ""
    var modified: Date = Date()
    var deleted: Bool = false

    var id: String { day }
    var recordName: String { "v-" + day }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Devam eden emzirmenin diğer telefona gösterilen hâli.
struct SharedNursing: Codable, Equatable {
    var active: ActiveNursing?
    var author: String
    var device: String
    var modified: Date
}

// MARK: Kontrol ve aşı takvimi

/// T.C. Sağlık Bakanlığı'nın bebek izlem ve çocukluk dönemi aşı takvimine göre, ilk iki yıl (Kasım 2026 itibarıyla).
/// Kesin tarihleri aile hekimi belirler; uygulama yalnızca hatırlatır.
struct ScheduleItem: Identifiable {
    let key: String
    let title: String
    let detail: String
    let days: Int
    let months: Int

    var id: String { key }

    func due(birth: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: birth)
        if months > 0 { return cal.date(byAdding: .month, value: months, to: start) ?? start }
        return cal.date(byAdding: .day, value: days, to: start) ?? start
    }
}

enum Schedule {
    static let items: [ScheduleItem] = [
        ScheduleItem(key: "first-days", title: "İlk günler", detail: "Topuk kanı (48–72. saat), işitme taraması, K vitamini ve Hepatit B aşısının 1. dozu. Genellikle hastanede yapılır.", days: 2, months: 0),
        ScheduleItem(key: "check-15d", title: "15. gün kontrolü", detail: "Tartı ve muayene.", days: 15, months: 0),
        ScheduleItem(key: "check-41d", title: "41. gün kontrolü", detail: "Muayene ve kalça çıkıklığı değerlendirmesi.", days: 41, months: 0),
        ScheduleItem(key: "m2", title: "2. ay kontrolü ve aşıları", detail: "BCG (verem), karma aşı 1. doz, KPA (zatürre) 1. doz.", days: 0, months: 2),
        ScheduleItem(key: "m3", title: "3. ay kontrolü", detail: "Tartı ve muayene.", days: 0, months: 3),
        ScheduleItem(key: "m4", title: "4. ay kontrolü ve aşıları", detail: "Karma aşı 2. doz, KPA 2. doz.", days: 0, months: 4),
        ScheduleItem(key: "m6", title: "6. ay kontrolü ve aşıları", detail: "Karma aşı 3. doz, ağızdan çocuk felci aşısı (OPA) 1. doz.", days: 0, months: 6),
        ScheduleItem(key: "m9", title: "9. ay kontrolü ve aşısı", detail: "KKK (kızamık, kızamıkçık, kabakulak) ek doz.", days: 0, months: 9),
        ScheduleItem(key: "m12", title: "12. ay kontrolü ve aşıları", detail: "KPA pekiştirme, KKK 1. doz, suçiçeği.", days: 0, months: 12),
        ScheduleItem(key: "m18", title: "18. ay kontrolü ve aşıları", detail: "Karma aşı pekiştirme, OPA 2. doz, Hepatit A 1. doz.", days: 0, months: 18),
        ScheduleItem(key: "m24", title: "24. ay kontrolü ve aşısı", detail: "Hepatit A 2. doz.", days: 0, months: 24),
    ]
}

extension Fmt {
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static func decimal(_ v: Double) -> String {
        numberFormatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// 3450 -> "3,45 kg"
    static func kg(_ grams: Int) -> String {
        String(format: "%.2f", Double(grams) / 1000).replacingOccurrences(of: ".", with: ",") + " kg"
    }

    static func date(_ d: Date) -> String { dateFormatter.string(from: d) }

    /// Virgüllü ya da noktalı sayı metnini okur.
    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v > 0 else { return nil }
        return v
    }

    /// "3 gün sonra", "bugün", "2 gün geçti"
    static func relativeDay(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if d == 0 { return "bugün" }
        if d == 1 { return "yarın" }
        if d > 1 && d < 60 { return "\(d) gün sonra" }
        if d >= 60 { return "\(d / 30) ay sonra" }
        if d == -1 { return "dün" }
        return "\(-d) gün geçti"
    }
}
