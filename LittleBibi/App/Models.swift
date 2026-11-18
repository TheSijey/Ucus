import Foundation

enum Side: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Sol" : "Sağ" }
}

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case nursing, bottle, diaper, sleep, burp, note
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nursing: return "Emzirme"
        case .bottle: return "Biberon"
        case .diaper: return "Bez"
        case .sleep: return "Uyku"
        case .burp: return "Gaz"
        case .note: return "Not"
        }
    }

    var symbol: String {
        switch self {
        case .nursing: return "heart.fill"
        case .bottle: return "waterbottle.fill"
        case .diaper: return "drop.fill"
        case .sleep: return "moon.zzz.fill"
        case .burp: return "wind"
        case .note: return "square.and.pencil"
        }
    }
}

enum DiaperType: String, Codable, CaseIterable, Identifiable {
    case wet, dirty, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wet: return "Islak"
        case .dirty: return "Kirli"
        case .both: return "İkisi de"
        }
    }
    var isWet: Bool { self != .dirty }
    var isDirty: Bool { self != .wet }
}

enum BottleContent: String, Codable, CaseIterable, Identifiable {
    case formula, breastMilk
    var id: String { rawValue }
    var title: String { self == .formula ? "Mama" : "Anne sütü" }
}

/// Tek bir bakım kaydı. Silinenler eşitleme için işaretli tutulur (deleted).
struct Entry: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: EntryKind
    var start: Date
    var end: Date? = nil
    var leftSeconds: Int = 0
    var rightSeconds: Int = 0
    var lastSide: Side? = nil
    var amountML: Int? = nil
    var bottleContent: BottleContent? = nil
    var diaper: DiaperType? = nil
    var note: String = ""
    var author: String = ""
    var modified: Date = Date()
    var deleted: Bool = false

    var isFeed: Bool { kind == .nursing || kind == .bottle }

    /// Listelerde gösterilen kısa açıklama.
    var detail: String {
        switch kind {
        case .nursing:
            var parts: [String] = []
            if leftSeconds > 0 { parts.append("Sol \(Fmt.duration(Double(leftSeconds)))") }
            if rightSeconds > 0 { parts.append("Sağ \(Fmt.duration(Double(rightSeconds)))") }
            return parts.isEmpty ? "Süre girilmedi" : parts.joined(separator: " · ")
        case .bottle:
            var parts: [String] = []
            if let ml = amountML, ml > 0 { parts.append("\(ml) ml") }
            if let c = bottleContent { parts.append(c.title) }
            return parts.joined(separator: " · ")
        case .diaper:
            switch diaper ?? .wet {
            case .wet: return "Islak"
            case .dirty: return "Kirli"
            case .both: return "Islak ve kirli"
            }
        case .sleep:
            if let end { return Fmt.duration(end.timeIntervalSince(start)) }
            return "Uyuyor"
        case .burp:
            return "Gaz çıkardı"
        case .note:
            return note
        }
    }
}

struct Profile: Codable, Equatable {
    var babyName: String = ""
    var birthDate: Date? = nil
    var myName: String = ""
    var onboarded: Bool = false
    /// Bebek bilgilerinin son değiştiği an; aile eşitlemesinde hangisinin yeni olduğunu belirler.
    var babyModified: Date? = nil
    /// DSÖ büyüme eğrileri için. Eski kayıtlarla uyum için isteğe bağlı.
    var babySex: BabySex? = nil
}

enum BabySex: String, Codable, CaseIterable, Identifiable {
    case girl, boy
    var id: String { rawValue }
    var title: String { self == .girl ? "Kız" : "Erkek" }
}

/// Profilin aileyle paylaşılan kısmı.
struct SharedProfile: Codable {
    var babyName: String
    var birthDate: Date?
    var modified: Date
    var babySex: BabySex? = nil
}

/// Devam eden emzirme. Uygulama kapansa da kaybolmaması için diske yazılır.
struct ActiveNursing: Codable, Equatable {
    var id = UUID()
    var startedAt: Date
    var side: Side? = nil
    var runningSince: Date? = nil
    var left: Double = 0
    var right: Double = 0

    var isRunning: Bool { runningSince != nil }

    func elapsed(_ s: Side, at now: Date) -> Double {
        let base = s == .left ? left : right
        if side == s, let since = runningSince {
            return base + max(0, now.timeIntervalSince(since))
        }
        return base
    }

    func total(at now: Date) -> Double { elapsed(.left, at: now) + elapsed(.right, at: now) }

    /// Çalışan dilimi biriken süreye ekleyip saati durdurur.
    mutating func stopClock(at now: Date) {
        if let since = runningSince, let s = side {
            let add = max(0, now.timeIntervalSince(since))
            if s == .left { left += add } else { right += add }
        }
        runningSince = nil
    }
}

/// Belirli bir zaman aralığının özeti (nöbet devri ve günlük toplamlar).
struct Summary {
    var nursingCount = 0
    var nursingSeconds = 0.0
    var bottleCount = 0
    var bottleML = 0
    var wet = 0
    var dirty = 0
    var diapers = 0
    var sleepSeconds = 0.0
    var burps = 0

    var feedCount: Int { nursingCount + bottleCount }

    static func make(_ entries: [Entry], from: Date, to: Date) -> Summary {
        var s = Summary()
        for e in entries {
            if e.kind == .sleep {
                let a = max(e.start, from)
                let b = min(e.end ?? to, to)
                if b > a { s.sleepSeconds += b.timeIntervalSince(a) }
                continue
            }
            guard e.start >= from, e.start <= to else { continue }
            switch e.kind {
            case .nursing:
                s.nursingCount += 1
                s.nursingSeconds += Double(e.leftSeconds + e.rightSeconds)
            case .bottle:
                s.bottleCount += 1
                s.bottleML += e.amountML ?? 0
            case .diaper:
                let d = e.diaper ?? .wet
                s.diapers += 1
                if d.isWet { s.wet += 1 }
                if d.isDirty { s.dirty += 1 }
            case .burp:
                s.burps += 1
            case .sleep, .note:
                break
            }
        }
        return s
    }
}

enum Fmt {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd.MM.yyyy;HH:mm"
        return f
    }()

    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }
    static func stamp(_ d: Date) -> String { stampFormatter.string(from: d) }

    /// "1 sa 20 dk", "14 dk", "1 dk'dan az"
    static func duration(_ seconds: Double) -> String {
        let m = Int(max(0, seconds) / 60)
        if m < 1 { return "1 dk'dan az" }
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) dk" }
        if r == 0 { return "\(h) sa" }
        return "\(h) sa \(r) dk"
    }

    static func ago(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "Az önce" }
        return "\(duration(s)) önce"
    }

    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Bugün" }
        if cal.isDateInYesterday(d) { return "Dün" }
        return dayFormatter.string(from: d)
    }

    /// "12 günlük", "3 aylık", "1 yaşında"
    static func age(birth: Date, now: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: birth), to: cal.startOfDay(for: now)).day ?? 0
        if days < 0 { return "" }
        if days == 0 { return "Bugün doğdu" }
        if days < 60 { return "\(days) günlük" }
        let months = cal.dateComponents([.month], from: birth, to: now).month ?? 0
        if months < 24 { return "\(months) aylık" }
        return "\(months / 12) yaşında"
    }
}
