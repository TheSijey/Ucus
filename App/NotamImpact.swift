import Foundation
import SwiftUI

/// NOTAM'dan çıkarılan operasyonel etki: "Pist 16L/34R kapalı", "ILS 27R arızalı", "Taksi yolu K4, K5 kapalı" ...
/// Kurallarla (yapay zekâsız) çıkarılır; yapay zekâ olmayan cihazlarda da aynı sonuç.
struct NotamImpact: Hashable, Identifiable {
    enum Kind: String {
        case aerodrome, runway, runwayLength, ils, approach, navaid, gnss, rff, fuel, taxiway, stand, lighting, obstacle, birds, airspace

        var icon: String {
            switch self {
            case .aerodrome: "xmark.octagon"
            case .runway, .runwayLength: "road.lanes"
            case .ils, .approach: "airplane.arrival"
            case .navaid: "antenna.radiowaves.left.and.right"
            case .gnss: "location.slash"
            case .rff: "flame"
            case .fuel: "fuelpump"
            case .taxiway: "arrow.triangle.turn.up.right.diamond"
            case .stand: "parkingsign"
            case .lighting: "lightbulb.slash"
            case .obstacle: "exclamationmark.triangle"
            case .birds: "bird"
            case .airspace: "square.dashed"
            }
        }
    }

    let kind: Kind
    let text: String
    let level: Notam.Level
    var id: String { "\(kind.rawValue)|\(text)" }
}

enum NotamAnalyzer {
    // Cümle sınırını (". ") aşmadan en fazla 60 karakter
    private static let gap = #"(?:(?!\. ).){0,60}?"#
    private static let rwy = #"RWY\s*(\d{2}[LRC]?(?:\s*/\s*\d{2}[LRC]?)?)"#
    private static let unserviceable = #"(U/S|UNSERVICEABLE|NOT AVBL|NOT AVAILABLE|OUT OF SERVICE|WITHDRAWN|SUSPENDED|INOP)"#

    private static func first(_ pattern: String, _ s: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > group, let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }
    private static func groups(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }
    private static func has(_ pattern: String, _ s: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }

    /// NOTAM'ın operasyonel etkileri (boş olabilir).
    static func impacts(_ n: Notam) -> [NotamImpact] {
        let e = " " + n.text.uppercased() + " "
        let q = n.qcode.uppercased()
        let subject = q.count == 5 ? String(q.dropFirst().prefix(2)) : ""
        var out: [NotamImpact] = []
        func add(_ k: NotamImpact.Kind, _ tr: String, _ en: String, _ lv: Notam.Level) {
            let i = NotamImpact(kind: k, text: L(tr, en), level: lv)
            if !out.contains(i) { out.append(i) }
        }
        let runway = first(rwy, e)?.replacingOccurrences(of: " ", with: "")
        let lda = first(#"LDA\s*(\d{3,4})\s*M"#, e)

        if has(#"\bAD\s+(CLSD|CLOSED)\b"#, e) { add(.aerodrome, "Meydan kapalı", "Aerodrome closed", .critical) }

        // Pist kapalı (taksi yolu/apron NOTAM'ındaki "RWY" atfı sayılmasın)
        if let r = runway, has(#"\bRWY\s*\d{2}[LRC]?(?:\s*/\s*\d{2}[LRC]?)?\s*(?:(?!TWY\b|AND\b)\w+\s+){0,3}?(CLSD|CLOSED)\b"#, e)
            || (subject == "MR" && has(#"\b(CLSD|CLOSED)\b"#, e) && !has(#"\bTWY\b"#, e)) {
            add(.runway, "Pist \(r) kapalı", "RWY \(r) closed", .critical)
        }
        // Eşik kaydırma / kısalan pist
        if let r = runway, has(#"\bTHR\b"# + gap + #"\bDISPLACED\b"#, e) {
            add(.runwayLength, "Pist \(r) eşik kaydırıldı" + (lda.map { " (LDA \($0) m)" } ?? ""),
                "RWY \(r) threshold displaced" + (lda.map { " (LDA \($0) m)" } ?? ""), .critical)
        } else if let r = runway, has(#"\b(TORA|LDA|TODA|ASDA)\b"#, e) || has(#"\b(SHORTENED|REDUCED LENGTH)\b"#, e) {
            add(.runwayLength, "Pist \(r) kısaldı" + (lda.map { " (LDA \($0) m)" } ?? ""),
                "RWY \(r) shortened" + (lda.map { " (LDA \($0) m)" } ?? ""), .critical)
        }
        // ILS / LOC / GP
        if let g = groups(#"\b(ILS|LOC|LLZ|GP|GS)\b"# + gap + rwy + gap + #"\b"# + unserviceable, e)
            ?? groups(rwy + gap + #"\b(ILS|LOC|LLZ|GP|GS)\b"# + gap + #"\b"# + unserviceable, e).map({ [$0[0], $0[2], $0[1]] }) {
            let sys = g[1] == "LLZ" ? "LOC" : (g[1] == "GS" ? "GP" : g[1])
            let r = g[2].replacingOccurrences(of: " ", with: "")
            add(.ils, "\(sys) \(r) arızalı", "\(sys) \(r) unserviceable", .critical)
        } else if ["IC", "IG", "IL", "ID"].contains(subject), has(#"\b"# + unserviceable, e) {
            add(.ils, "ILS \(runway ?? "") arızalı".replacingOccurrences(of: "  ", with: " "), "ILS \(runway ?? "") unserviceable", .critical)
        }
        // Aletli yaklaşma prosedürü
        if let g = groups(#"\b(RNP|RNAV|VOR|NDB|LOC)\b(?:\s+[XYZ])?"# + gap + #"(?:APCH|APPROACH|IAP)"# + gap + #"\b"# + unserviceable, e) {
            add(.approach, "\(g[1]) yaklaşma\(runway.map { " \($0)" } ?? "") kullanılamaz", "\(g[1]) approach\(runway.map { " \($0)" } ?? "") not available", .important)
        }
        // Seyrüsefer yardımcıları (ILS dışında)
        if out.allSatisfy({ $0.kind != .ils && $0.kind != .approach }),
           let g = groups(#"\b(VOR/DME|DVOR/DME|VOR|DVOR|DME|NDB|TACAN|VORTAC)\b\s*([A-Z]{2,3})?\b"# + gap + #"\b"# + unserviceable, e) {
            add(.navaid, "\(g[1])\(g[2].isEmpty ? "" : " \(g[2])") arızalı", "\(g[1])\(g[2].isEmpty ? "" : " \(g[2])") unserviceable", .important)
        }
        // GNSS parazit
        if has(#"\b(GNSS|GPS)\b"#, e), has(#"\b(RFI|INTERFERENCE|JAMMING|SPOOFING|UNRELIABLE|NOT AVBL|OUTAGE)\b"#, e) || subject.hasPrefix("G") {
            add(.gnss, "GNSS parazit / kesinti", "GNSS interference / outage", .important)
        }
        // Yangın-kurtarma kategorisi
        if let c = first(#"\b(?:RFFS?|FIRE\s*FIGHTING|RESCUE)\b"# + gap + #"CAT(?:EGORY)?\s*(\d{1,2})"#, e) {
            add(.rff, "RFF kategorisi \(c)", "RFF category \(c)", .critical)
        }
        if has(#"\bFUEL\b"#, e), has(#"\b(NOT AVBL|UNAVBL|LTD|LIMITED|SHORTAGE|RESTRICTED)\b"#, e) {
            add(.fuel, "Yakıt kısıtlı", "Fuel limited", .important)
        }
        // Taksi yolları
        if let list = first(#"\bTWY\s+((?:[A-Z]{1,2}\d{0,2}[A-Z]?)(?:\s*(?:,|/|AND|&)\s*(?:TWY\s+)?[A-Z]{1,2}\d{0,2}[A-Z]?)*)"#, e),
           has(#"\b(CLSD|CLOSED|NOT AVBL)\b"#, e) {
            let names = list.replacingOccurrences(of: #"\s*(,|/|AND|&)\s*(TWY\s+)?"#, with: ", ", options: .regularExpression)
            add(.taxiway, "Taksi yolu \(names) kapalı", "TWY \(names) closed", .important)
        }
        // Stand / apron
        if let st = first(#"\bSTANDS?\s+([A-Z]?\d{1,3}[A-Z]?(?:\s*(?:-|,|/|TO|AND)\s*[A-Z]?\d{1,3}[A-Z]?)*)"#, e),
           has(#"\b(CLSD|CLOSED|NOT AVBL|U/S)\b"#, e) {
            let s = st.replacingOccurrences(of: " ", with: "")
            add(.stand, "Stand \(s) kapalı", "Stand \(s) closed", .info)
        } else if let ap = first(#"\bAPRON\s+([A-Z0-9]{1,3})\b"#, e), has(#"\b(CLSD|CLOSED)\b"#, e) {
            add(.stand, "Apron \(ap) kapalı", "Apron \(ap) closed", .info)
        }
        // Işıklar
        if let g = groups(#"\b(ALS|PAPI|VASIS|RCLL|RCL|REDL|RTZL|TDZ|HIRL|SALS)\b"# + gap + rwy + gap + #"\b"# + unserviceable, e) {
            add(.lighting, "\(g[1]) \(g[2].replacingOccurrences(of: " ", with: "")) arızalı", "\(g[1]) \(g[2].replacingOccurrences(of: " ", with: "")) unserviceable", .important)
        }
        // Engel / vinç: yaklaşma ya da kalkış yönündeyse önemli
        if has(#"\b(CRANE|OBST|OBSTACLE)\b"#, e), !has(#"\bLGT\b"# + gap + #"\b"# + unserviceable, e) {
            let h = first(#"(\d{2,4})\s*FT"#, e)
            add(.obstacle, "Engel / vinç" + (h.map { " \($0) ft" } ?? ""), "Obstacle / crane" + (h.map { " \($0) ft" } ?? ""),
                has(#"\b(APCH|DEP|FINAL|THR|TKOF)\b"#, e) ? .important : .info)
        }
        if has(#"\bBIRD"#, e) { add(.birds, "Kuş yoğunluğu", "Bird activity", .info) }
        if ["RD", "RR", "RP", "RT", "RA"].contains(subject) { add(.airspace, "Sahasal kısıtlama", "Airspace restriction", .info) }
        return out.sorted { $0.level < $1.level }
    }

    /// Kurallara göre seviye: etki varsa en yüksek etkisi, yoksa Q kodundan.
    static func level(_ n: Notam) -> Notam.Level {
        if let top = impacts(n).map(\.level).min() { return top }
        let q = n.qcode.uppercased()
        let subject = q.count == 5 ? String(q.dropFirst().prefix(2)) : ""
        let condition = q.count == 5 ? String(q.suffix(2)) : ""
        let bad = ["LC", "AS", "AU", "AW", "LT", "LD"].contains(condition)
        if ["MR", "FA", "IC", "IG", "IL"].contains(subject) && bad { return .critical }
        if ["MX", "MN", "LA", "LP", "NV", "ND", "NB", "NM", "PI", "PA", "PD", "FU", "GA", "GW", "FF"].contains(subject) && (bad || condition == "XX") { return .important }
        return .info
    }

    // MARK: - D) programı: "DLY 2200-0400", "MON-FRI 0600-1400"

    struct Schedule { let start: Int; let end: Int; let weekdays: Set<Int>? }   // dakika (UTC), 1=Pazar…7=Cumartesi

    static func schedules(_ n: Notam) -> [Schedule]? {
        let src = (n.schedule.isEmpty ? (first(#"\b((?:DLY|DAILY|MON|TUE|WED|THU|FRI|SAT|SUN)[A-Z\s\-,]*\d{4}\s*-\s*\d{4}(?:\s*,?\s*\d{4}\s*-\s*\d{4})*)"#, " " + n.text.uppercased() + " ") ?? "") : n.schedule).uppercased()
        guard !src.isEmpty else { return nil }
        guard let re = try? NSRegularExpression(pattern: #"(\d{2})(\d{2})\s*-\s*(\d{2})(\d{2})"#) else { return nil }
        let matches = re.matches(in: src, range: NSRange(src.startIndex..., in: src))
        guard !matches.isEmpty else { return nil }   // anlaşılmadıysa nil: hep etkin say
        let days = weekdays(src)
        return matches.compactMap { m in
            let v = (1...4).compactMap { Range(m.range(at: $0), in: src).flatMap { Int(src[$0]) } }
            guard v.count == 4, v[0] < 24, v[2] <= 24 else { return nil }
            return Schedule(start: v[0] * 60 + v[1], end: v[2] * 60 + v[3], weekdays: days)
        }
    }

    private static func weekdays(_ s: String) -> Set<Int>? {
        let names = ["SUN": 1, "MON": 2, "TUE": 3, "WED": 4, "THU": 5, "FRI": 6, "SAT": 7]
        if s.contains("DLY") || s.contains("DAILY") { return nil }
        var set = Set<Int>()
        if let re = try? NSRegularExpression(pattern: #"\b(SUN|MON|TUE|WED|THU|FRI|SAT)\s*-\s*(SUN|MON|TUE|WED|THU|FRI|SAT)\b"#) {
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                guard let a = Range(m.range(at: 1), in: s).flatMap({ names[String(s[$0])] }),
                      let b = Range(m.range(at: 2), in: s).flatMap({ names[String(s[$0])] }) else { continue }
                var d = a
                for _ in 0..<7 { set.insert(d); if d == b { break }; d = d % 7 + 1 }
            }
        }
        for (k, v) in names where s.range(of: "\\b\(k)\\b", options: .regularExpression) != nil { set.insert(v) }
        return set.isEmpty ? nil : set
    }

    /// NOTAM verilen zaman aralıklarından birinde etkin mi? (B–C ve D programı)
    static func isActive(_ n: Notam, in windows: [ClosedRange<Date>]) -> Bool {
        let start = n.from ?? .distantPast, end = n.to ?? .distantFuture
        let validWindows = windows.filter { $0.lowerBound <= end && $0.upperBound >= start }
        guard !validWindows.isEmpty else { return false }
        guard let sch = schedules(n), !sch.isEmpty else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        for w in validWindows {
            var day = cal.startOfDay(for: w.lowerBound.addingTimeInterval(-86_400))
            while day <= w.upperBound {
                let wd = cal.component(.weekday, from: day)
                for s in sch where s.weekdays?.contains(wd) ?? true {
                    let a = day.addingTimeInterval(Double(s.start) * 60)
                    var b = day.addingTimeInterval(Double(s.end) * 60)
                    if s.end <= s.start { b = b.addingTimeInterval(86_400) }
                    if a <= w.upperBound && b >= w.lowerBound { return true }
                }
                day = day.addingTimeInterval(86_400)
            }
        }
        return false
    }

    /// Kısa saat etiketi: D) programı varsa "22:00–04:00Z", kısa süreliyse bitiş.
    static func timeTag(_ n: Notam) -> String? {
        if let s = schedules(n)?.first {
            return String(format: "%02d:%02d–%02d:%02dZ", s.start / 60, s.start % 60, s.end / 60, s.end % 60)
        }
        if let to = n.to, to.timeIntervalSinceNow < 3 * 86_400 { return "→ " + FlightHelpers.utc(to) }
        return nil
    }

    /// Yapay zekâ özetini koruma: özetteki pist/taksi yolu/navaid kimlikleri NOTAM metninde yoksa özet atılır.
    static func summaryIsFaithful(_ summary: String, raw: String) -> Bool {
        let up = raw.uppercased().replacingOccurrences(of: " ", with: "")
        guard let re = try? NSRegularExpression(pattern: #"\b(\d{2}[LRC]?|[A-Z]{1,2}\d{1,3}[A-Z]?)\b"#) else { return true }
        let s = summary.uppercased()
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range(at: 1), in: s) else { continue }
            let token = String(s[r])
            if token.count >= 2, token.contains(where: \.isNumber), !up.contains(token) { return false }
        }
        return true
    }
}
