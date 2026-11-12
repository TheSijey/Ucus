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
        let (m, t) = await (metars, tafs)

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
            return w
        }
        if result.contains(where: { $0.metar != nil || $0.taf != nil }) {
            cache[key] = (Date(), result)
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

/// Uygulamadaki "Hava durumu" bölümü.
struct WeatherSection: View {
    let icaos: [String]
    let reloadKey: Date
    @State private var items: [AirportWeather] = []
    @State private var loading = false

    var body: some View {
        Section {
            if loading && items.isEmpty {
                HStack { ProgressView(); Text("Hava durumu alınıyor…").foregroundStyle(.secondary) }
            }
            ForEach(items) { w in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(w.icao).font(.headline.monospaced())
                        if let c = w.category {
                            Text(c)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(color(c).opacity(0.25), in: Capsule())
                                .foregroundStyle(color(c))
                        }
                        Spacer()
                        if let t = w.metarTime {
                            (Text(t, style: .relative) + Text(" önce"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(w.metar ?? "METAR yok")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    if let taf = w.taf {
                        Text(taf)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Hava durumu")
        } footer: {
            Text("Kaynak: aviationweather.gov. 10 dakikada bir yenilenir.")
        }
        .task(id: "\(icaos.joined())|\(reloadKey.timeIntervalSince1970)") {
            loading = true
            let r = await WeatherService.fetch(icaos)
            if !r.isEmpty { items = r }
            loading = false
        }
    }

    private func color(_ cat: String) -> Color {
        switch cat {
        case "VFR": .green
        case "MVFR": .blue
        case "IFR": .red
        case "LIFR": .purple
        default: .gray
        }
    }
}
