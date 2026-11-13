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
    var runways: [String] = []   // "16L/34R" ...
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

    /// Pist listeleri (kalıcı önbellek; pistler değişmez).
    private static let runwayCacheKey = "runwayCache"
    static let knownRunways: [String: [String]] = [
        "LTFM": ["16L/34R", "16R/34L", "17L/35R", "17R/35L", "18/36"],
    ]

    private static func runwayInfo(_ ids: [String]) async -> [String: [String]] {
        var cache = (UserDefaults.standard.dictionary(forKey: runwayCacheKey) as? [String: [String]]) ?? [:]
        let missing = ids.filter { (cache[$0] ?? []).isEmpty && knownRunways[$0] == nil }
        if !missing.isEmpty {
            for row in await load("airport", ids: missing.joined(separator: ",")) {
                guard let icao = row["icaoId"] as? String else { continue }
                let list = (row["runways"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                if !list.isEmpty { cache[icao] = list }
            }
            UserDefaults.standard.set(cache, forKey: runwayCacheKey)
        }
        var result = knownRunways
        for id in ids where result[id] == nil { result[id] = cache[id] ?? [] }
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
    var activeRunways: [String: String] = [:]   // "LTFM": "35R" (CDM kalkış pisti)
    var events: [String: [WeatherEvent]] = [:]  // meydan → kalkış/iniş saatleri (TAF'ta işaretlenir)
    @State private var items: [AirportWeather] = []
    @State private var loading = false

    var body: some View {
        let highlights = items.flatMap { WeatherHighlights.scan(icao: $0.icao, metar: $0.metar, taf: $0.taf) }
        if !items.isEmpty {
            Section("Önemli durumlar") {
                if highlights.isEmpty {
                    Label("Dikkat çeken bir durum yok", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                ForEach(highlights, id: \.self) { h in
                    Label(h, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
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
                            MinutesAgo(date: t)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(w.metar ?? "METAR yok")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    windView(w)
                    eventsHeader(events[w.icao] ?? [])
                    if let taf = w.taf {
                        tafView(taf, events: events[w.icao] ?? [])
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

    @ViewBuilder
    private func windView(_ w: AirportWeather) -> some View {
        if let metar = w.metar, let wind = Wind.parse(metar) {
            let comps = WindCalc.components(wind: wind, runways: w.runways)
            let active = activeRunways[w.icao]
            if wind.direction == nil {
                Text("Rüzgâr değişken \(wind.speed) kt").font(.caption).foregroundStyle(.secondary)
            } else if !comps.isEmpty {
                // Aktif pist (CDM) önce, sonra en iyi karşı rüzgârlı 3 pist ucu
                let ordered = comps.filter { $0.runway == active } + comps.filter { $0.runway != active }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ordered.prefix(4)) { c in
                        HStack(spacing: 6) {
                            Text(c.runway)
                                .font(.caption.monospaced().bold())
                                .frame(width: 34, alignment: .leading)
                                .foregroundStyle(c.runway == active ? .cyan : .primary)
                            Text(c.head >= 0 ? "karşı \(c.head)" : "arka \(-c.head)")
                                .foregroundStyle(c.head >= 0 ? Color.primary : Color.orange)
                            Text("· yan \(c.cross)\(c.crossFromLeft ? " sol" : " sağ")")
                            if let gc = c.gustCross, let gh = c.gustHead {
                                Text("(G: \(gh >= 0 ? "k" : "a")\(abs(gh)) / y\(gc))").foregroundStyle(.secondary)
                            }
                            if c.runway == active { Text("aktif").font(.caption2).foregroundStyle(.cyan) }
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func eventsHeader(_ evs: [WeatherEvent]) -> some View {
        if !evs.isEmpty {
            HStack(spacing: 10) {
                ForEach(evs, id: \.self) { e in
                    HStack(spacing: 4) {
                        Circle().fill(e.isReturn ? Color.blue : Color.green).frame(width: 8, height: 8)
                        Text("\(e.label) \(utc(e.time))Z").bold()
                    }
                }
            }
            .font(.caption.monospacedDigit())
            .padding(.top, 2)
        }
    }

    private func tafView(_ taf: String, events evs: [WeatherEvent]) -> some View {
        let groups = TafParser.groups(taf)
        let applicable = evs.map { TafParser.applicable(groups, event: $0.time) }
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(groups) { g in
                let hits = evs.indices.filter { applicable[$0].contains(g.id) }.map { evs[$0] }
                let tint: Color? = hits.contains(where: { !$0.isReturn }) && hits.contains(where: { $0.isReturn })
                    ? .teal : hits.first.map { $0.isReturn ? .blue : .green }
                HStack(alignment: .top, spacing: 6) {
                    Rectangle()
                        .fill(tint ?? Color.gray.opacity(0.3))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.text)
                            .font(.caption2.monospaced())
                            .foregroundStyle(tint == nil ? Color.secondary : Color.primary)
                            .fontWeight(tint == nil ? .regular : .semibold)
                        if !hits.isEmpty {
                            Text(hits.map { "\($0.label) \(utc($0.time))Z" }.joined(separator: " · "))
                                .font(.caption2.bold())
                                .foregroundStyle(tint ?? .primary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 4)
                .background((tint ?? .clear).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .textSelection(.enabled)
    }

    private func utc(_ d: Date) -> String {
        var st = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        st.timeZone = TimeZone(identifier: "UTC")!
        st.locale = Locale(identifier: "en_GB")
        return d.formatted(st)
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
