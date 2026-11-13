import SwiftUI

/// Hava: meydan seçici, METAR özeti, pist rüzgârı, işaretli TAF.
struct WeatherTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared
    @State private var items: [AirportWeather] = []
    @State private var selected = "LTFM"
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = session.state {
                    let airports = FlightHelpers.airports(s)
                    VStack(spacing: 12) {
                        if airports.count > 1 {
                            Picker("Meydan", selection: $selected) {
                                ForEach(airports, id: \.self) { icao in
                                    Text(label(icao, s)).tag(icao)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        highlights
                        if let w = items.first(where: { $0.icao == selected }) {
                            metarCard(w)
                            RunwayWindCard(weather: w,
                                           active: selected == "LTFM" ? s.runway : "",
                                           history: selected == "LTFM" ? [] : (s.turn?.destRunwayHistory ?? []))
                                .id(w.icao)
                            if let taf = w.taf {
                                tafCard(taf, events: FlightHelpers.weatherEvents(s)[w.icao] ?? [])
                            }
                        } else if loading {
                            ProgressView().padding(40)
                        } else {
                            Text("Hava durumu alınamadı.").foregroundStyle(Palette.secondary).padding(40)
                        }
                        Text("Kaynak: aviationweather.gov · 10 dk'da bir yenilenir · bilgi amaçlıdır")
                            .font(.caption2).foregroundStyle(Palette.secondary)
                    }
                    .padding(16)
                    .task(id: "\(airports.joined())|\(s.updatedAt.timeIntervalSince1970)") {
                        loading = true
                        let r = await WeatherService.fetch(airports)
                        if !r.isEmpty { items = r }
                        if !airports.contains(selected) { selected = "LTFM" }
                        loading = false
                    }
                } else {
                    EmptyFlightView().padding(.top, 60)
                }
            }
            .background(Palette.bg)
            .navigationTitle("Hava")
            .toolbar { CommonToolbar() }
            .refreshable { await model.refresh() }
        }
    }

    private func label(_ icao: String, _ s: FlightAttributes.ContentState) -> String {
        if icao == "LTFM" { return "LTFM · İstanbul" }
        if let t = s.turn, t.destICAO == icao, !t.destCity.isEmpty { return "\(icao) · \(t.destCity)" }
        return icao
    }

    // MARK: Önemli durumlar

    @ViewBuilder
    private var highlights: some View {
        let list = items.flatMap { WeatherHighlights.scan(icao: $0.icao, metar: $0.metar, taf: $0.taf) }
        if !items.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Önemli durumlar").font(.headline)
                    if list.isEmpty {
                        Label("Dikkat çeken bir durum yok", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Palette.outbound)
                    }
                    ForEach(list, id: \.self) { h in
                        Label(h, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(Palette.warn)
                    }
                }
            }
        }
    }

    // MARK: METAR

    private func metarCard(_ w: AirportWeather) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("METAR").font(.headline)
                    if let c = w.category {
                        Text(c).font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(catColor(c).opacity(0.2), in: Capsule())
                            .foregroundStyle(catColor(c))
                    }
                    Spacer()
                    if let t = w.metarTime { MinutesAgo(date: t).font(.caption).foregroundStyle(Palette.secondary) }
                }
                if let m = w.metar {
                    let sum = MetarSummary(m)
                    HStack(spacing: 8) {
                        Tile(title: "Rüzgâr", value: sum.wind)
                        Tile(title: "Görüş", value: sum.visibility)
                        Tile(title: "QNH", value: sum.qnh)
                    }
                    Text(m).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.85)).textSelection(.enabled)
                } else {
                    Text("METAR yok").foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func catColor(_ c: String) -> Color {
        switch c {
        case "VFR": Palette.outbound
        case "MVFR": Palette.ret
        case "IFR": .red
        case "LIFR": .purple
        default: .gray
        }
    }

    // MARK: TAF

    private func tafCard(_ taf: String, events: [WeatherEvent]) -> some View {
        let groups = TafParser.groups(taf)
        let applicable = events.map { TafParser.applicable(groups, event: $0.time) }
        let hitsFor: (TafGroup) -> [WeatherEvent] = { g in events.indices.filter { applicable[$0].contains(g.id) }.map { events[$0] } }

        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TAF").font(.headline)
                    Spacer()
                    ForEach(events, id: \.self) { e in
                        HStack(spacing: 4) {
                            Circle().fill(e.isReturn ? Palette.ret : Palette.outbound).frame(width: 8, height: 8)
                            Text("\(e.label) \(FlightHelpers.utc(e.time))")
                        }
                        .font(.caption2.monospacedDigit())
                    }
                }
                ForEach(groups) { g in groupRow(g, hits: hitsFor(g)) }
            }
        }
    }

    private func groupRow(_ g: TafGroup, hits: [WeatherEvent]) -> some View {
        let tint: Color? = hits.contains(where: { !$0.isReturn }) && hits.contains(where: { $0.isReturn })
            ? .teal : hits.first.map { $0.isReturn ? Palette.ret : Palette.outbound }
        return VStack(alignment: .leading, spacing: 3) {
            if !hits.isEmpty {
                Text(hits.map { "\($0.label) \(FlightHelpers.utc($0.time))" }.joined(separator: " · ") + " · geçerli")
                    .font(.caption.bold()).foregroundStyle(tint ?? .white)
            }
            Text(g.text).font(.caption.monospaced())
                .foregroundStyle(tint == nil ? Palette.secondary : .white)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((tint ?? Color.white).opacity(tint == nil ? 0.04 : 0.13),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// METAR'dan kısa özet: rüzgâr, görüş, QNH.
struct MetarSummary {
    let wind: String
    let visibility: String
    let qnh: String

    init(_ metar: String) {
        if let w = Wind.parse(metar) {
            let dir = w.direction.map { String(format: "%03d°", $0) } ?? "VRB"
            wind = "\(dir) \(w.speed)" + (w.gust.map { "G\($0)" } ?? "") + " kt"
        } else { wind = "—" }
        let tokens = metar.split(separator: " ").map(String.init)
        if tokens.contains("CAVOK") { visibility = "CAVOK" }
        else if let v = tokens.first(where: { $0.range(of: #"^\d{4}$"#, options: .regularExpression) != nil }) {
            visibility = v == "9999" ? "10 km+" : "\(Int(v) ?? 0) m"
        } else { visibility = "—" }
        if let q = tokens.first(where: { $0.range(of: #"^Q\d{4}$"#, options: .regularExpression) != nil }) {
            qnh = String(q.dropFirst())
        } else if let a = tokens.first(where: { $0.range(of: #"^A\d{4}$"#, options: .regularExpression) != nil }) {
            qnh = "\(a.dropFirst(1).prefix(2)).\(a.suffix(2)) inHg"
        } else { qnh = "—" }
    }
}

/// Kompakt pist rüzgârı kartı (pilot görünümü): pist yukarı doğru, yeşil karşı / kırmızı arka, turuncu yan.
struct RunwayWindCard: View {
    let weather: AirportWeather
    let active: String          // CDM aktif pisti (İstanbul)
    let history: [String]       // son seferlerde varışta kullanılan pistler
    @State private var selected: String?

    var body: some View {
        if let m = weather.metar, let wind = Wind.parse(m) {
            Card {
                if wind.direction == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pist rüzgârı").font(.headline)
                        Text("Rüzgâr değişken \(wind.speed) kt").font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                } else {
                    content(wind: wind, comps: WindCalc.components(wind: wind, runways: weather.runways))
                }
            }
        }
    }

    @ViewBuilder
    private func content(wind: Wind, comps: [RunwayWind]) -> some View {
        let pick = defaultPick(comps)
        let current = comps.first { $0.runway == (selected ?? pick.runway) } ?? comps.first
        if let c = current {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pist \(c.runway)").font(.headline)
                    Text("· \(String(format: "%03d", c.heading))°" + (c.lengthM.map { " · \($0.formatted(.number.locale(Locale(identifier: "tr_TR")))) m" } ?? ""))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                    Spacer()
                    if let tag = tag(for: c.runway, pick: pick) {
                        Text(tag).font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.stand.opacity(0.18), in: Capsule())
                            .foregroundStyle(Palette.stand)
                    }
                }
                HStack(alignment: .center, spacing: 18) {
                    drawing(c, maxSpeed: max(wind.speed, wind.gust ?? 0))
                    VStack(alignment: .leading, spacing: 10) {
                        valueBlock(title: c.head >= 0 ? "karşı" : "arka", value: abs(c.head),
                                   gust: c.gustHead.map { abs($0) }, color: c.head >= 0 ? Palette.outbound : .red)
                        valueBlock(title: "yan · \(c.crossFromLeft ? "soldan" : "sağdan")", value: c.cross,
                                   gust: c.gustCross, color: Palette.warn)
                    }
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(comps) { r in
                            Button { selected = r.runway } label: {
                                Text(r.runway).font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(r.runway == c.runway ? Palette.stand : Palette.card2,
                                                in: RoundedRectangle(cornerRadius: 9))
                                    .foregroundStyle(r.runway == c.runway ? Color.black : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func defaultPick(_ comps: [RunwayWind]) -> (runway: String, reason: String) {
        if !active.isEmpty, comps.contains(where: { $0.runway == active }) { return (active, "aktif") }
        if let h = FlightHelpers.mostCommon(history), comps.contains(where: { $0.runway == h }) {
            return (h, "son seferlerde \(h)")
        }
        return (comps.first?.runway ?? "", "rüzgâra göre muhtemel")
    }

    private func tag(for runway: String, pick: (runway: String, reason: String)) -> String? {
        if runway == pick.runway { return pick.reason }
        if runway == active { return "aktif" }
        return nil
    }

    private func valueBlock(title: String, value: Int, gust: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(value) kt").font(.title3.bold()).foregroundStyle(color)
                Text(title).font(.subheadline).foregroundStyle(color.opacity(0.85))
            }
            if let gust, gust != value {
                Text("hamle \(gust) kt").font(.caption).foregroundStyle(Palette.secondary)
            }
        }
    }

    /// Küçük çizim: pist yukarı doğru, oklar bileşenleri gösterir.
    private func drawing(_ c: RunwayWind, maxSpeed: Int) -> some View {
        let h: CGFloat = 120
        let scale = CGFloat(max(maxSpeed, 1))
        let headLen = max(10, CGFloat(abs(c.head)) / scale * 46)
        let crossLen = max(10, CGFloat(c.cross) / scale * 34)
        return ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.24)).frame(width: 26, height: h)
            Rectangle().fill(Color.white.opacity(0.6)).frame(width: 2, height: h - 34)
                .mask(VStack(spacing: 6) { ForEach(0..<8, id: \.self) { _ in Rectangle().frame(height: 6) } })
            VStack {
                Spacer()
                Text(c.runway).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white).padding(.bottom, 3)
            }
            .frame(height: h)
            // Karşı (yukarıdan aşağı) / arka (aşağıdan yukarı)
            if c.head != 0 {
                VStack(spacing: 0) {
                    if c.head > 0 {
                        Rectangle().frame(width: 4, height: headLen)
                        Image(systemName: "arrowtriangle.down.fill").font(.system(size: 11))
                        Spacer()
                    } else {
                        Spacer()
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: 11))
                        Rectangle().frame(width: 4, height: headLen)
                    }
                }
                .foregroundStyle(c.head > 0 ? Palette.outbound : .red)
                .frame(height: h)
                .offset(x: -26)
            }
            // Yan: rüzgârın geldiği taraftan pistin üzerine doğru
            if c.cross > 0 {
                HStack(spacing: 0) {
                    if c.crossFromLeft {
                        Rectangle().frame(width: crossLen, height: 4)
                        Image(systemName: "arrowtriangle.right.fill").font(.system(size: 11))
                    } else {
                        Image(systemName: "arrowtriangle.left.fill").font(.system(size: 11))
                        Rectangle().frame(width: crossLen, height: 4)
                    }
                }
                .foregroundStyle(Palette.warn)
                .offset(x: c.crossFromLeft ? -(13 + crossLen / 2 + 6) : (13 + crossLen / 2 + 6), y: 4)
            }
        }
        .frame(width: 110, height: h)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pist \(c.runway): \(c.head >= 0 ? "karşı" : "arka") \(abs(c.head)) knot, yan \(c.cross) knot")
    }
}
