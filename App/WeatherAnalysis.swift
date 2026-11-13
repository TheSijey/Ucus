import Foundation

/// METAR rüzgârı.
struct Wind: Hashable {
    let direction: Int?   // nil = VRB
    let speed: Int
    let gust: Int?

    /// "35012G25KT", "VRB03KT", "00000KT" (MPS da desteklenir, kt'a çevrilir)
    static func parse(_ metar: String) -> Wind? {
        guard let re = try? NSRegularExpression(pattern: #"\b(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)\b"#),
              let m = re.firstMatch(in: metar, range: NSRange(metar.startIndex..., in: metar)) else { return nil }
        func g(_ i: Int) -> String? { Range(m.range(at: i), in: metar).map { String(metar[$0]) } }
        let factor = g(4) == "MPS" ? 1.944 : 1.0
        guard let spdS = g(2), let spd = Int(spdS) else { return nil }
        let gust = g(3).flatMap(Int.init).map { Int((Double($0) * factor).rounded()) }
        return Wind(direction: g(1).flatMap(Int.init), speed: Int((Double(spd) * factor).rounded()), gust: gust)
    }
}

/// Bir pist ucu için rüzgâr bileşenleri.
struct RunwayWind: Hashable, Identifiable {
    var id: String { runway }
    let runway: String      // "35R"
    let head: Int           // + karşı, - arka
    let cross: Int          // mutlak
    let crossFromLeft: Bool
    let gustHead: Int?
    let gustCross: Int?
}

enum WindCalc {
    /// "16L/34R" -> ["16L", "34R"]
    static func ends(_ designators: [String]) -> [String] {
        designators.flatMap { $0.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespaces) } }
            .filter { $0.range(of: #"^\d{1,2}[LRC]?$"#, options: .regularExpression) != nil }
    }

    static func heading(_ end: String) -> Double? {
        let digits = end.prefix { $0.isNumber }
        guard let n = Int(digits) else { return nil }
        return Double(n == 0 ? 36 : n) * 10
    }

    static func components(wind: Wind, runways: [String]) -> [RunwayWind] {
        guard let dir = wind.direction else { return [] }
        return ends(runways).compactMap { end in
            guard let hdg = heading(end) else { return nil }
            let diff = (Double(dir) - hdg) * .pi / 180
            func comp(_ s: Int) -> (Int, Int, Bool) {
                let h = Double(s) * cos(diff)
                let c = Double(s) * sin(diff)
                return (Int(h.rounded()), Int(abs(c).rounded()), c < 0)
            }
            let base = comp(wind.speed)
            let gust = wind.gust.map(comp)
            return RunwayWind(runway: end, head: base.0, cross: base.1, crossFromLeft: base.2,
                              gustHead: gust?.0, gustCross: gust?.1)
        }
        .sorted { $0.head > $1.head }
    }
}

/// METAR/TAF'ta dikkat çeken durumların kısa özeti (bilgi amaçlı, limit yok).
enum WeatherHighlights {
    static func scan(icao: String, metar: String?, taf: String?) -> [String] {
        var out: [String] = []
        if let m = metar {
            let items = significant(in: strip(m))
            if !items.isEmpty { out.append("\(icao): " + items.joined(separator: ", ")) }
        }
        if let t = taf {
            for group in tafGroups(t) {
                let items = significant(in: group.body)
                if !items.isEmpty { out.append("\(icao) TAF \(group.header): " + items.joined(separator: ", ")) }
            }
        }
        return out
    }

    /// METAR'ın sonundaki trend/RMK kısmını at.
    private static func strip(_ m: String) -> String {
        var s = m
        for cut in [" RMK ", " NOSIG", " TEMPO ", " BECMG "] {
            if let r = s.range(of: cut) { s = String(s[..<r.lowerBound]) }
        }
        return s
    }

    private struct Group { let header: String; let body: String }

    private static func tafGroups(_ taf: String) -> [Group] {
        let tokens = taf.split(separator: " ").map(String.init)
        var groups: [Group] = []
        var header = "ana"
        var body: [String] = []
        var i = 0
        func flush() { if !body.isEmpty { groups.append(Group(header: header, body: body.joined(separator: " "))) } }
        while i < tokens.count {
            let t = tokens[i]
            if ["TEMPO", "BECMG"].contains(t) || t.hasPrefix("PROB") || t.hasPrefix("FM") && t.count >= 8 {
                flush()
                body = []
                if t.hasPrefix("PROB"), i + 1 < tokens.count, tokens[i + 1] == "TEMPO" {
                    header = "\(t) TEMPO"; i += 1
                } else {
                    header = t
                }
                if i + 1 < tokens.count, tokens[i + 1].contains("/"), tokens[i + 1].count == 9 {
                    header += " " + tokens[i + 1]; i += 1
                }
            } else {
                body.append(t)
            }
            i += 1
        }
        flush()
        return groups
    }

    private static func significant(in text: String) -> [String] {
        var r: [String] = []
        let tokens = text.split(separator: " ").map(String.init)

        if let w = Wind.parse(text) {
            if let g = w.gust { r.append("hamle \(g) kt") }
            else if w.speed >= 20 { r.append("rüzgâr \(w.speed) kt") }
        }
        // Görüş (4 haneli metre) – rüzgârdan sonra gelen ilk 4 haneli sayı
        for t in tokens where t.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            if let v = Int(t), v < 1500 { r.append("görüş \(v) m") }
            break
        }
        if tokens.contains(where: { $0.hasPrefix("R") && $0.contains("/") && $0.range(of: #"^R\d{2}[LRC]?/"#, options: .regularExpression) != nil }) {
            r.append("RVR var")
        }
        // Tavan
        for t in tokens {
            if let m = t.range(of: #"^(BKN|OVC|VV)(\d{3})"#, options: .regularExpression) {
                let s = String(t[m])
                if let h = Int(s.suffix(3)), h * 100 < 1000 {
                    r.append("\(s.prefix(s.count - 3)) \(h * 100) ft")
                    break
                }
            }
        }
        // Hadiseler
        let wx: [(String, String)] = [("TS", "oraj"), ("CB", "CB"), ("TCU", "TCU"), ("FZ", "donan yağış/sis"),
                                      ("SN", "kar"), ("GR", "dolu"), ("GS", "küçük dolu"), ("+RA", "kuvvetli yağmur"),
                                      ("FG", "sis"), ("SQ", "bora"), ("FC", "hortum"), ("SS", "kum fırtınası"),
                                      ("DS", "toz fırtınası"), ("PL", "buz taneleri")]
        for (code, name) in wx where tokens.contains(where: { tok in
            code == "CB" || code == "TCU" ? tok.hasSuffix(code) : tok.contains(code) && !tok.hasPrefix("RE")
        }) {
            if !r.contains(name) { r.append(name) }
        }
        return r
    }
}
