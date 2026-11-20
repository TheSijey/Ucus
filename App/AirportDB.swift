import Foundation

/// IATA → ICAO ve şehir (OurAirports'tan, büyük ve orta meydanlar). AeroDataBox'a ihtiyaç duymadan
/// CDM'deki varış kodundan (BEY) hava durumu meydanını (OLBA) bulmak için.
enum AirportDB {
    private static let table: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "iata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return t
    }()

    static func icao(_ iata: String) -> String? { table[iata.uppercased()]?.first }
    static func city(_ iata: String) -> String? { table[iata.uppercased()].flatMap { $0.count > 1 ? $0[1] : nil } }
    struct Hit: Hashable { let icao: String; let iata: String; let city: String }

    /// Kod (ICAO/IATA) ya da şehir adıyla arama: "LHR", "EGLL", "lon", "amman".
    static func search(_ raw: String, limit: Int = 8) -> [Hit] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        let fq = fold(q)
        let up = q.uppercased()
        var exact: [Hit] = []
        var byCity: [Hit] = []
        for (iata, v) in table {
            guard let icao = v.first else { continue }
            let city = v.count > 1 ? v[1] : ""
            if iata == up || icao == up { exact.append(Hit(icao: icao, iata: iata, city: city)); continue }
            if q.count >= 3, fold(city).hasPrefix(fq) || fold(city).contains(" " + fq) { byCity.append(Hit(icao: icao, iata: iata, city: city)) }
        }
        var out = exact + byCity.sorted { $0.city == $1.city ? $0.iata < $1.iata : $0.city < $1.city }
        // Tabloda olmayan 4 harfli ICAO da açılabilsin
        if up.count == 4, up.allSatisfy({ $0.isLetter }), !out.contains(where: { $0.icao == up }) {
            out.insert(Hit(icao: up, iata: "", city: ""), at: 0)
        }
        return Array(out.prefix(limit))
    }

    static func city(icao: String) -> String? {
        table.first { $0.value.first == icao.uppercased() }.flatMap { $0.value.count > 1 ? $0.value[1] : nil }
    }
}
