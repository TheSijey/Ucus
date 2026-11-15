import Foundation
import PDFKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Model

struct Notam: Identifiable, Codable, Hashable {
    enum Level: Int, Codable, Comparable, CaseIterable {
        case critical = 0, important = 1, info = 2
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .critical: L("Kritik", "Critical")
            case .important: L("Önemli", "Important")
            case .info: L("Bilgi", "Info")
            }
        }
        var color: Color {
            switch self {
            case .critical: Color(red: 1, green: 0.38, blue: 0.38)
            case .important: Palette.warn
            case .info: Palette.secondary
            }
        }
    }

    var id: String                 // "A1234/26"
    var location: String = ""      // A) LTFM
    var qcode: String = ""         // QMRLC
    var from: Date?                // B)
    var to: Date?                  // C) (nil = PERM / belirsiz)
    var toEstimated = false
    var schedule: String = ""      // D)
    var text: String               // E)
    var raw: String
    var level: Level = .info
    var summary: String?           // yapay zekâ özeti
}

struct NotamPackage: Codable {
    var importedAt = Date()
    var source: String
    var notams: [Notam]
    var alternates: [String]? = nil   // yedek meydanlar (briefing'den bulunan ya da elle girilen)
}

/// NOTAM'ın uçuştaki yeri.
enum NotamGroup: Int, CaseIterable, Identifiable {
    case departure, destination, alternate, enroute
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .departure: L("Kalkış", "Departure")
        case .destination: L("Varış", "Destination")
        case .alternate: L("Yedek", "Alternate")
        case .enroute: L("Yol / FIR", "En route / FIR")
        }
    }

    var shortTitle: String {
        switch self {
        case .departure: L("Kalkış", "Dep")
        case .destination: L("Varış", "Dest")
        case .alternate: L("Yedek", "Altn")
        case .enroute: L("Yol", "Enrt")
        }
    }

    static func of(_ n: Notam, origin: String, dest: String?, alternates: [String]) -> NotamGroup {
        if n.location == origin { return .departure }
        if let dest, n.location == dest { return .destination }
        if alternates.contains(n.location) { return .alternate }
        return .enroute
    }
}

// MARK: - Ayrıştırma

enum NotamParser {
    private static let idPattern = #"(?<![A-Z0-9])([A-Z]\d{4}/\d{2})(?![0-9])"#

    /// Metindeki NOTAM'ları bulur (ICAO biçimi; Q) satırı yoksa da E) metni ve konum aranır).
    static func parse(_ text: String) -> [Notam] {
        let t = text.replacingOccurrences(of: "\r", with: "\n")
        guard let re = try? NSRegularExpression(pattern: idPattern) else { return [] }
        let ns = t as NSString
        let matches = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
        var out: [Notam] = []
        var seen = Set<String>()
        for (i, m) in matches.enumerated() {
            let start = m.range.location
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            // Bir sonraki NOTAM'ın önündeki konum kodu (ayrı satırda "EGLL") bu bloğun sonuna yapışmasın
            let block = ns.substring(with: NSRange(location: start, length: end - start))
                .replacingOccurrences(of: #"\n[ \t]*[A-Z]{4}[ \t]*$"#, with: "", options: .regularExpression)
            let id = ns.substring(with: m.range(at: 1))
            // Aynı NOTAM'a yapılan atıflar (NOTAMR A1234/26) ayrı blok sayılmasın: içerik çok kısaysa atla
            guard block.count > 25, !seen.contains(id) else { continue }
            var n = Notam(id: id, text: "", raw: block.trimmingCharacters(in: .whitespacesAndNewlines))
            n.qcode = capture(#"Q\)\s*[A-Z]{4}/(Q[A-Z]{4})"#, block) ?? ""
            n.location = capture(#"A\)\s*([A-Z]{4})"#, block) ?? ""
            n.from = capture(#"B\)\s*(\d{10})"#, block).flatMap(date)
            if let c = capture(#"C\)\s*(\d{10}|PERM)"#, block) {
                n.to = c == "PERM" ? nil : date(c)
                n.toEstimated = block.range(of: #"C\)\s*\d{10}\s*EST"#, options: .regularExpression) != nil
            }
            n.schedule = capture(#"D\)\s*(.+?)(?=\s+E\)|\n)"#, block) ?? ""
            if let e = capture(#"E\)\s*([\s\S]+?)(?=\s+[FG]\)\s|\z)"#, block) {
                n.text = clean(e)
            } else {
                // Q) satırı olmayan (LIDO tarzı) biçim: kimlikten sonraki metin
                n.text = clean(String(block.dropFirst(id.count)))
            }
            // Briefing paketlerinde konum çoğu zaman kimlikten önce yazılır: "EGLL C0567/26 ..."
            if n.location.isEmpty {
                let before = ns.substring(with: NSRange(location: max(0, start - 12), length: min(12, start)))
                if let loc = capture(#"\b([A-Z]{4})\s*$"#, before) { n.location = loc }
            }
            if n.location.isEmpty, let loc = capture(#"\b(L[A-Z]{3}|E[A-Z]{3}|K[A-Z]{3}|O[A-Z]{3}|U[A-Z]{3})\b"#, String(block.prefix(80))) {
                n.location = loc
            }
            n.level = NotamClassifier.level(n)
            seen.insert(id)
            out.append(n)
        }
        return out
    }

    static func pdfText(_ url: URL) -> String? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            return PDFDocument(url: url)?.string
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capture(_ pattern: String, _ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// Briefing metnindeki yedek meydanlar: "ALTN EGSS", "ALTN: EGSS/EGKK", "ALTERNATE EGSS" ...
    static func alternates(in text: String, excluding: [String]) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\b(?:ALTN|ALTERNATES?|DEST ALTN|ERA|TO ALTN)\b[\s:/-]*((?:[A-Z]{4}\b[\s,/]*){1,4})"#) else { return [] }
        let ns = text as NSString
        let stop: Set<String> = ["ALTN", "NONE", "TEMP", "FROM", "TAKE", "FUEL", "TIME", "DIST", "PLAN", "WIND", "ROUTE"]
        var out: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let chunk = ns.substring(with: m.range(at: 1))
            for code in chunk.split(whereSeparator: { !$0.isLetter }).map(String.init) where code.count == 4 {
                if !excluding.contains(code), !out.contains(code), !stop.contains(code) {
                    out.append(code)
                }
            }
        }
        return Array(out.prefix(4))
    }

    /// "2611140600" → 14 Kasım 2026 06:00 UTC
    static func date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmm"
        return f.date(from: s)
    }
}

// MARK: - Sınıflandırma (kurallarla, yapay zekâsız)

enum NotamClassifier {
    static func level(_ n: Notam) -> Notam.Level {
        let q = n.qcode.uppercased()
        let e = " " + n.text.uppercased() + " "
        let subject = q.count == 5 ? String(q.dropFirst().prefix(2)) : ""
        let condition = q.count == 5 ? String(q.suffix(2)) : ""
        let badCondition = ["LC", "AS", "AU", "AW", "CC", "LT", "AL", "AK", "XX"].contains(condition)

        // Kritik: pist, ILS/GP/LOC, aletli yaklaşma, meydan kapalı
        if ["MR", "IC", "IG", "IL", "ID", "IS", "PI", "FA"].contains(subject) && badCondition { return .critical }
        let criticalWords = [#"\bRWY\b[^.]*\bCLSD\b"#, #"\bAD\b[^.]*\bCLSD\b"#, #"\b(ILS|LOC|GP|GS|LLZ)\b[^.]*\b(U/S|NOT AVBL|UNSERVICEABLE|OUT OF SERVICE)\b"#,
                             #"\bRWY\b[^.]*\bNOT AVBL\b"#, #"\bTHR\b[^.]*\bDISPLACED\b"#, #"\bTORA\b|\bLDA\b|\bTODA\b"#]
        if criticalWords.contains(where: { e.range(of: $0, options: .regularExpression) != nil }) { return .critical }

        // Önemli: taksi yolu, apron/stand, ışıklar, seyrüsefer yardımcıları, yakıt, prosedür değişikliği
        if ["MX", "MN", "MP", "MS", "MK"].contains(subject) || subject.hasPrefix("L") || subject.hasPrefix("N") || subject == "FU" || subject.hasPrefix("P") { return .important }
        let importantWords = [#"\bTWY\b"#, #"\bSTAND\b|\bSTANDS\b|\bAPRON\b"#, #"\bLGT\b|\bALS\b|\bPAPI\b|\bVASIS\b"#,
                              #"\bVOR\b|\bDME\b|\bNDB\b"#, #"\bSID\b|\bSTAR\b|\bIAP\b|\bRNP\b|\bRNAV\b"#, #"\bFUEL\b"#, #"\bDE-?ICING\b"#]
        if importantWords.contains(where: { e.range(of: $0, options: .regularExpression) != nil }) { return .important }
        return .info
    }

    /// Uçuş saatinde geçerli mi? (D) programı dikkate alınmaz, sadece B–C aralığı)
    static func isActive(_ n: Notam, from: Date, to: Date) -> Bool {
        let start = n.from ?? .distantPast
        let end = n.to ?? .distantFuture
        return start <= to && end >= from
    }
}

// MARK: - Kısaltmaları açma (yapay zekâ yoksa da çalışır)

enum NotamDecoder {
    private static let table: [String: (String, String)] = [
        "RWY": ("pist", "runway"), "TWY": ("taksi yolu", "taxiway"), "CLSD": ("kapalı", "closed"),
        "U/S": ("arızalı", "unserviceable"), "AVBL": ("kullanılabilir", "available"), "NOT AVBL": ("kullanılamaz", "not available"),
        "WIP": ("çalışma var", "work in progress"), "DUE": ("nedeniyle", "due to"), "MAINT": ("bakım", "maintenance"),
        "LGT": ("ışık", "lighting"), "THR": ("eşik", "threshold"), "APCH": ("yaklaşma", "approach"),
        "ACFT": ("uçak", "aircraft"), "OBST": ("engel", "obstacle"), "CRANE": ("vinç", "crane"),
        "HGT": ("yükseklik", "height"), "ELEV": ("rakım", "elevation"), "BTN": ("arasında", "between"),
        "EXC": ("hariç", "except"), "DLY": ("her gün", "daily"), "FM": ("itibaren", "from"), "TIL": ("kadar", "until"),
        "PSN": ("konum", "position"), "VCY": ("civarı", "vicinity"), "BIRD": ("kuş", "bird"), "ACT": ("aktif", "active"),
        "INFO": ("bilgi", "information"), "PPR": ("önceden izin gerekli", "prior permission required"),
        "ABN": ("havaalanı ışıklı fener", "aerodrome beacon"), "ALS": ("yaklaşma ışıkları", "approach lights"),
        "STAND": ("stand", "stand"), "APRON": ("apron", "apron"), "TEMPO": ("geçici", "temporarily"),
        "CTN": ("dikkat", "caution"), "OPS": ("operasyon", "operations"), "REF": ("bkz.", "refer to"),
    ]

    static func decode(_ text: String) -> String {
        var s = text
        for (k, v) in table.sorted(by: { $0.key.count > $1.key.count }) {
            let word = Lang.isEnglish ? v.1 : v.0
            s = s.replacingOccurrences(of: #"(?<![A-Z])\#(NSRegularExpression.escapedPattern(for: k))(?![A-Z])"#,
                                       with: word, options: .regularExpression)
        }
        return s
    }
}

// MARK: - Yapay zekâ özeti (Apple'ın cihaz içi modeli)

enum NotamAI {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Tek NOTAM için tek cümlelik özet. Model yoksa nil.
    static func summarize(_ n: Notam) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let lang = Lang.isEnglish ? "English" : "Turkish"
            let session = LanguageModelSession(instructions: """
                You summarize aviation NOTAMs for airline pilots. Reply with ONE short plain-language sentence in \(lang), \
                max 20 words, stating the operational impact (what is closed/unavailable/changed, where, and when if short). \
                Keep runway, taxiway, stand and navaid identifiers exactly as written. Never add information that is not in the NOTAM.
                """)
            do {
                let r = try await session.respond(to: "Location: \(n.location)\nNOTAM: \(n.text)")
                let out = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty ? nil : out
            } catch {
                DebugLog.add("NOTAM özeti hatası: \(error.localizedDescription)")
                return nil
            }
        }
        #endif
        return nil
    }
}

// MARK: - Depo

@MainActor
final class NotamStore: ObservableObject {
    static let shared = NotamStore()
    @Published private(set) var packages: [String: NotamPackage] = [:]   // uçuş anahtarı → paket
    @Published var summarizing = false

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notams.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let p = try? JSONDecoder().decode([String: NotamPackage].self, from: data) {
            let limit = Date().addingTimeInterval(-3 * 86_400)
            packages = p.filter { $0.value.importedAt > limit }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(packages) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Metni ayrıştırıp uçuşa bağlar; NOTAM sayısını döndürür.
    @discardableResult
    func importText(_ text: String, source: String, key: String, airports: [String] = []) -> Int {
        let list = NotamParser.parse(text)
        // Briefing metninde (OFP) yedek meydan ara
        let alts = NotamParser.alternates(in: text, excluding: airports)
        packages[key] = NotamPackage(source: source, notams: list, alternates: alts.isEmpty ? nil : alts)
        persist()
        Task { await summarizeImportant(key) }
        return list.count
    }

    /// Paylaş menüsünden açılan dosyanın uygulama içindeki kopyasını siler (sadece kendi klasörümüzdekini).
    nonisolated static func removeCopy(_ url: URL) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL.path
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(docs) || path.hasPrefix(tmp) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Önceki sürümlerden kalan kopyaları temizler (Documents/Inbox).
    nonisolated static func purgeInbox() {
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Inbox")
        guard let items = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        items.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    func setAlternates(_ key: String, _ list: [String]) {
        guard var p = packages[key] else { return }
        p.alternates = list.isEmpty ? nil : list
        packages[key] = p
        persist()
    }

    func remove(_ key: String) {
        packages[key] = nil
        persist()
    }

    /// Kritik ve önemli NOTAM'ları sırayla özetler (en fazla 40).
    func summarizeImportant(_ key: String) async {
        guard NotamAI.isAvailable, !summarizing, var p = packages[key] else { return }
        summarizing = true
        defer { summarizing = false }
        let order = p.notams.indices.filter { p.notams[$0].level != .info && p.notams[$0].summary == nil }
            .sorted { p.notams[$0].level < p.notams[$1].level }
            .prefix(40)
        for i in order {
            if let s = await NotamAI.summarize(p.notams[i]) {
                p.notams[i].summary = s
                packages[key] = p
            }
        }
        persist()
    }
}
