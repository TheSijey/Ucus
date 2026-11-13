import SwiftUI

/// Hava: meydan seçici, METAR özeti, pist rüzgârı, işaretli TAF.
struct WeatherTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared
    @State private var items: [AirportWeather] = []
    @State private var selected = "LTFM"
    @State private var loading = false
    @State private var showOtherGroups = false

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
                            windCard(w, active: selected == "LTFM" ? s.runway : "")
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

    // MARK: Pist rüzgârı

    @ViewBuilder
    private func windCard(_ w: AirportWeather, active: String) -> some View {
        if let m = w.metar, let wind = Wind.parse(m) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pist rüzgârı").font(.headline)
                    if wind.direction == nil {
                        Text("Rüzgâr değişken \(wind.speed) kt").font(.subheadline).foregroundStyle(Palette.secondary)
                    } else {
                        let comps = WindCalc.components(wind: wind, runways: w.runways)
                        let ordered = comps.filter { $0.runway == active } + comps.filter { $0.runway != active }
                        let maxV = max(1, ordered.prefix(4).map { max(abs($0.head), $0.cross, $0.gustCross ?? 0) }.max() ?? 1)
                        ForEach(Array(ordered.prefix(4))) { c in
                            HStack(spacing: 10) {
                                Text(c.runway).font(.subheadline.monospaced().bold())
                                    .frame(width: 40, alignment: .leading)
                                    .foregroundStyle(c.runway == active ? Palette.stand : .white)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.1))
                                        Capsule().fill(c.head >= 0 ? Palette.outbound : Palette.warn)
                                            .frame(width: g.size.width * CGFloat(abs(c.head)) / CGFloat(maxV))
                                    }
                                }
                                .frame(height: 8)
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("\(c.head >= 0 ? "karşı" : "arka") \(abs(c.head)) · yan \(c.cross)\(c.crossFromLeft ? "◀︎" : "▶︎")")
                                    if let gc = c.gustCross, let gh = c.gustHead {
                                        Text("hamle: \(gh >= 0 ? "k" : "a")\(abs(gh)) / y\(gc)").foregroundStyle(Palette.secondary)
                                    }
                                }
                                .font(.caption.monospacedDigit())
                                .frame(width: 140, alignment: .trailing)
                            }
                        }
                        if !active.isEmpty {
                            Text("Mavi: CDM'deki aktif pist · pist yönü numaradan hesaplanır")
                                .font(.caption2).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: TAF

    private func tafCard(_ taf: String, events: [WeatherEvent]) -> some View {
        let groups = TafParser.groups(taf)
        let applicable = events.map { TafParser.applicable(groups, event: $0.time) }
        let hitsFor: (TafGroup) -> [WeatherEvent] = { g in events.indices.filter { applicable[$0].contains(g.id) }.map { events[$0] } }
        let marked = groups.filter { !hitsFor($0).isEmpty }
        let others = groups.filter { hitsFor($0).isEmpty }

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
                ForEach(marked) { g in groupRow(g, hits: hitsFor(g)) }
                if !others.isEmpty {
                    Button {
                        withAnimation { showOtherGroups.toggle() }
                    } label: {
                        HStack {
                            Text("Diğer gruplar (\(others.count))")
                            Image(systemName: showOtherGroups ? "chevron.up" : "chevron.down")
                        }
                        .font(.footnote).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if showOtherGroups {
                        ForEach(others) { g in groupRow(g, hits: []) }
                    }
                }
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
