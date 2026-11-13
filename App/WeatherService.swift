import Foundation
import SwiftUI

/// Bir meydanın METAR ve TAF'ı.
struct AirportWeather: Identifiable, Hashable {
    var id: String { icao }
    let icao: String
    var metar: String?
    var metarTime: Date?
    var taf: String?
    var category: String?   // VFR, MVFR, IFR, LIFR
    var runways: [RunwayData] = []   // pistler (gerçek yön ve uzunlukla)
}

/// aviationweather.gov (NOAA) – ücretsiz, anahtar gerektirmez.
enum WeatherService {
    private static var cache: [String: (date: Date, value: [AirportWeather])] = [:]

    static func fetch(_ icaos: [String]) async -> [AirportWeather] {
        let ids = icaos.map { $0.uppercased() }.filter { $0.count == 4 }
        guard !ids.isEmpty else { return [] }
        let key = ids.joined(separator: ",")
        if let c = cache[key], Date().timeIntervalSince(c.date) < 600 { return c.value }

        async let metars = load("metar", ids: key)
        async let tafs = load("taf", ids: key)
        async let airports = runwayInfo(ids)
        let (m, t, rw) = await (metars, tafs, airports)

        let result: [AirportWeather] = ids.map { icao in
            var w = AirportWeather(icao: icao)
            if let row = m.first(where: { ($0["icaoId"] as? String) == icao }) {
                w.metar = row["rawOb"] as? String
                if let ts = row["obsTime"] as? Double { w.metarTime = Date(timeIntervalSince1970: ts) }
                else if let ts = row["obsTime"] as? Int { w.metarTime = Date(timeIntervalSince1970: Double(ts)) }
                w.category = row["fltCat"] as? String
            }
            if let row = t.first(where: { ($0["icaoId"] as? String) == icao }) {
                w.taf = row["rawTAF"] as? String
            }
            w.runways = rw[icao] ?? []
            return w
        }
        if result.contains(where: { $0.metar != nil || $0.taf != nil }) {
            cache[key] = (Date(), result)
        }
        return result
    }

    /// Pist bilgileri (kalıcı önbellek; pistler değişmez).
    private static let runwayCacheKey = "runwayCache2"
    static let fallbackRunways: [String: [String]] = [
        "LTFM": ["16L/34R", "16R/34L", "17L/35R", "17R/35L", "18/36"],
    ]

    private static func runwayInfo(_ ids: [String]) async -> [String: [RunwayData]] {
        var cache = (UserDefaults.standard.dictionary(forKey: runwayCacheKey) as? [String: [[String: Any]]]) ?? [:]
        let missing = ids.filter { (cache[$0] ?? []).isEmpty }
        if !missing.isEmpty {
            for row in await load("airport", ids: missing.joined(separator: ",")) {
                guard let icao = row["icaoId"] as? String else { continue }
                let list: [[String: Any]] = (row["runways"] as? [[String: Any]] ?? []).compactMap { r in
                    guard let id = r["id"] as? String else { return nil }
                    var d: [String: Any] = ["id": id]
                    if let a = r["alignment"] as? Int { d["a"] = a }
                    else if let a = r["alignment"] as? String, let n = Int(a) { d["a"] = n }
                    if let dim = r["dimension"] as? String, let ft = Int(dim.split(separator: "x").first ?? "") {
                        d["l"] = Int(Double(ft) * 0.3048)
                    }
                    return d
                }
                if !list.isEmpty { cache[icao] = list }
            }
            UserDefaults.standard.set(cache, forKey: runwayCacheKey)
        }
        var result: [String: [RunwayData]] = [:]
        for id in ids {
            if let rows = cache[id], !rows.isEmpty {
                result[id] = rows.compactMap { r in
                    (r["id"] as? String).map { RunwayData(id: $0, alignment: r["a"] as? Int, lengthM: r["l"] as? Int) }
                }
            } else {
                result[id] = (fallbackRunways[id] ?? []).map { RunwayData(id: $0, alignment: nil, lengthM: nil) }
            }
        }
        return result
    }

    private static func load(_ kind: String, ids: String) async -> [[String: Any]] {
        guard let url = URL(string: "https://aviationweather.gov/api/data/\(kind)?ids=\(ids)&format=json") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Ucus-iOS/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let result = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [[String: Any]] else { return [] }
        return json
    }
}

