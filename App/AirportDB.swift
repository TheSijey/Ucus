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
    static func city(icao: String) -> String? {
        table.first { $0.value.first == icao.uppercased() }.flatMap { $0.value.count > 1 ? $0.value[1] : nil }
    }
}
