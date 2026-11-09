import Foundation

/// IGA CDM sonuç sayfasının metnini (document.body.innerText) okur.
/// Örnek sayfa:
///   TK 1751            OSL
///   THY5VZ     32Q - TCLTD
///   EOBT 05:30 / TOBT 05:30 / TSAT / CTOT / Gate A3A / Stand A3L / Runway / SID
enum CDMParser {
    static let labels: Set<String> = ["EOBT", "TOBT", "TSAT", "CTOT", "Gate", "Stand", "Runway", "SID"]
    static let signOnBeforeEOBT: TimeInterval = 75 * 60   // 1 saat 15 dk

    static func parse(_ text: String, now: Date = Date()) -> FlightAttributes.ContentState? {
        let lines = text
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "\t") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        func value(_ label: String) -> String? {
            for (i, line) in lines.enumerated() {
                if line == label {
                    guard i + 1 < lines.count else { return nil }
                    let next = lines[i + 1]
                    return labels.contains(next) ? nil : next
                }
                if line.hasPrefix(label + " ") {
                    let v = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
                    return v.isEmpty ? nil : v
                }
            }
            return nil
        }

        func time(_ label: String) -> Date? {
            guard let v = value(label), v.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
            else { return nil }
            return utcTime(v, near: now)
        }

        // Uçuş numarası: "TK 1751"
        guard let flightMatch = firstMatch(#"\bTK\s?(\d{1,4}[A-Z]?)\b"#, in: text) else { return nil }
        let flight = "TK" + flightMatch[1]

        // Tip ve tescil: "32Q - TCLTD"
        var type = "", reg = ""
        if let m = firstMatch(#"\b([A-Z0-9]{2,4})\s*-\s*TC-?([A-Z]{3})\b"#, in: text) {
            type = m[1]
            reg = "TC-" + m[2]
        }

        let callsign = firstMatch(#"\bTHY[A-Z0-9]{1,5}\b"#, in: text)?[0] ?? ""

        // Varış: tek başına duran 3 harf (etiket olmayan)
        let destination = lines.first {
            $0.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil && !labels.contains($0)
        } ?? lines.compactMap { line -> String? in
            // "TK 1751 OSL" gibi aynı satırdaysa
            guard line.contains(flightMatch[0]) else { return nil }
            return firstMatch(#"\b([A-Z]{3})\s*$"#, in: line)?[1]
        }.first ?? ""

        let eobt = time("EOBT")
        let tobt = time("TOBT")
        let base = eobt ?? tobt ?? now.addingTimeInterval(signOnBeforeEOBT)

        return .init(
            flight: flight,
            callsign: callsign,
            registration: reg,
            aircraftType: type,
            destination: destination,
            gate: value("Gate") ?? "",
            stand: value("Stand") ?? "",
            eobt: eobt,
            tobt: tobt,
            tsat: time("TSAT"),
            ctot: time("CTOT"),
            signOn: base.addingTimeInterval(-signOnBeforeEOBT),
            updatedAt: now
        )
    }

    /// "05:30" (UTC) -> şu ana en yakın tarih. Sayfada sadece saat var, gün yok.
    static func utcTime(_ hhmm: String, near now: Date) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = parts[0]
        comps.minute = parts[1]
        guard var date = cal.date(from: comps) else { return nil }
        // Uçuşlar genelde önümüzdeki saatlerde: 6 saatten eskiyse yarına, 18 saatten ilerdeyse düne al.
        if date < now.addingTimeInterval(-6 * 3600) { date = cal.date(byAdding: .day, value: 1, to: date)! }
        if date > now.addingTimeInterval(18 * 3600) { date = cal.date(byAdding: .day, value: -1, to: date)! }
        return date
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
