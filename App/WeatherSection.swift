import SwiftUI

/// Hava bölümü (Brifing içinde): meydan seçici, önemli durumlar, METAR özeti, pist rüzgârı, işaretli TAF.
struct WeatherSection: View {
    @ObservedObject var session = FlightSession.shared
    @State private var items: [AirportWeather] = []
    @State private var selected = "LTFM"
    @State private var loading = false
    @State private var pickedByUser = false

    var body: some View {
        if let s = session.state {
            let airports = FlightHelpers.airports(s)
            VStack(spacing: 12) {
                if airports.count > 1 {
                    Picker(L("Meydan", "Airport"), selection: Binding(get: { selected }, set: { selected = $0; pickedByUser = true })) {
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
                                   active: activeRunway(s),
                                   history: s.isOutstation || selected == "LTFM" ? [] : (s.turn?.destRunwayHistory ?? []),
                                   event: nextEvent(s))
                        .id(w.icao)
                    if let taf = w.taf {
                        tafCard(taf, events: FlightHelpers.weatherEvents(s)[w.icao] ?? [])
                    }
                } else if loading {
                    ProgressView().padding(40)
                } else {
                    Text(L("Hava durumu alınamadı.", "Couldn't load weather.")).foregroundStyle(Palette.secondary).padding(40)
                }
                Text(L("Kaynak: aviationweather.gov · 10 dk'da bir yenilenir · bilgi amaçlıdır", "Source: aviationweather.gov · refreshed every 10 min · for information only"))
                    .font(.caption2).foregroundStyle(Palette.secondary)
            }
            .task(id: "\(airports.joined())|\(s.updatedAt.timeIntervalSince1970)") {
                loading = true
                let r = await WeatherService.fetch(airports)
                if !r.isEmpty { items = r }
                if !airports.contains(selected) || (s.isOutstation && selected == "LTFM" && !pickedByUser) { selected = airports.first ?? "LTFM" }
                loading = false
            }
        }
    }

    private func label(_ icao: String, _ s: FlightAttributes.ContentState) -> String {
        if icao == "LTFM" { return "LTFM · İstanbul" }
        if icao == s.origin, let c = s.originCity, !c.isEmpty { return "\(icao) · \(c)" }
        if let t = s.turn, t.destICAO == icao, !t.destCity.isEmpty { return "\(icao) · \(t.destCity)" }
        if let c = AirportDB.city(s.destination), AirportDB.icao(s.destination) == icao { return "\(icao) · \(c)" }
        return icao
    }

    // MARK: Önemli durumlar

    @ViewBuilder
    private var highlights: some View {
        let list = items.flatMap { WeatherHighlights.scan(icao: $0.icao, metar: $0.metar, taf: $0.taf) }
        if !items.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Önemli durumlar", "Notable items")).font(.headline)
                    if list.isEmpty {
                        Label(L("Dikkat çeken bir durum yok", "Nothing notable"), systemImage: "checkmark.circle.fill")
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
                        Tile(title: L("Rüzgâr", "Wind"), value: sum.wind)
                        Tile(title: L("Görüş", "Visibility"), value: sum.visibility)
                        Tile(title: "QNH", value: sum.qnh)
                    }
                    Text(m).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.85)).textSelection(.enabled)
                } else {
                    Text(L("METAR yok", "No METAR")).foregroundStyle(Palette.secondary)
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

    /// CDM pisti sadece kalkış meydanında ve kalkıştan (10 dk sonrasına) kadar geçerli.
    private func activeRunway(_ s: FlightAttributes.ContentState) -> String {
        guard selected == (s.origin ?? "LTFM") else { return "" }
        if let dep = s.departureTime, Date() > dep.addingTimeInterval(10 * 60) { return "" }
        return s.runway
    }

    /// Bu meydandaki sıradaki kalkış/iniş (15 dk önce geçmiş olanlar dahil).
    private func nextEvent(_ s: FlightAttributes.ContentState) -> WeatherEvent? {
        (FlightHelpers.weatherEvents(s)[selected] ?? [])
            .filter { $0.time > Date().addingTimeInterval(-15 * 60) }
            .min { $0.time < $1.time }
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
                Text(hits.map { "\($0.label) \(FlightHelpers.utc($0.time))" }.joined(separator: " · ") + L(" · geçerli", " · applies"))
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
    let active: String          // CDM aktif pisti (İstanbul, kalkıştan önce)
    let history: [String]       // son seferlerde varışta kullanılan pistler
    var event: WeatherEvent? = nil   // bu meydandaki sıradaki kalkış/iniş
    @State private var selected: String?

    /// Olay 45 dk'dan uzaksa TAF'taki o saatin rüzgârı, değilse METAR.
    private var forecast: (wind: Wind, source: String, label: String?)? {
        if let ev = event, ev.time.timeIntervalSinceNow > 45 * 60,
           let taf = weather.taf, let w = TafParser.wind(taf, at: ev.time), w.direction != nil {
            return (w, "TAF", ev.label)
        }
        guard let m = weather.metar, let w = Wind.parse(m) else { return nil }
        return (w, "METAR", nil)
    }

    var body: some View {
        if let f = forecast {
            let wind = f.wind
            Card {
                if wind.direction == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Pist rüzgârı", "Runway wind")).font(.headline)
                        Text(L("Rüzgâr değişken \(wind.speed) kt", "Wind variable \(wind.speed) kt")).font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                } else {
                    content(wind: wind, comps: WindCalc.components(wind: wind, runways: weather.runways), source: f.source, label: f.label)
                }
            }
        }
    }

    @ViewBuilder
    private func content(wind: Wind, comps: [RunwayWind], source: String, label: String?) -> some View {
        let pick = defaultPick(comps, label: label)
        let current = comps.first { $0.runway == (selected ?? pick.runway) } ?? comps.first
        if let c = current {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Pist", "Runway") + " \(c.runway)").font(.headline)
                    Text("· \(String(format: "%03d", c.heading))°" + (c.lengthM.map { " · \($0.formatted(.number.locale(Lang.locale))) m" } ?? ""))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                    Spacer()
                    if let tag = tag(for: c.runway, pick: pick) {
                        Text(tag).font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.stand.opacity(0.18), in: Capsule())
                            .foregroundStyle(Palette.stand)
                    }
                }
                Text(windLine(wind, source: source, label: label))
                    .font(.caption).foregroundStyle(source == "TAF" ? (event?.isReturn == true ? Palette.ret : Palette.outbound) : Palette.secondary)
                drawing(c, maxSpeed: max(wind.speed, wind.gust ?? 0))
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

    private func windLine(_ w: Wind, source: String, label: String?) -> String {
        let dir = w.direction.map { String(format: "%03d°", $0) } ?? "VRB"
        let value = "\(dir) \(w.speed)" + (w.gust.map { "G\($0)" } ?? "") + " kt"
        if source == "TAF", let label, let t = event?.time {
            return L("\(label) \(FlightHelpers.utc(t)) için TAF rüzgârı: \(value)", "TAF wind for \(label.lowercased()) \(FlightHelpers.utc(t)): \(value)")
        }
        return L("Şu anki rüzgâr (METAR): \(value)", "Current wind (METAR): \(value)")
    }

    private func defaultPick(_ comps: [RunwayWind], label: String?) -> (runway: String, reason: String) {
        if !active.isEmpty, comps.contains(where: { $0.runway == active }) { return (active, L("aktif", "active")) }
        if let h = FlightHelpers.mostCommon(history), comps.contains(where: { $0.runway == h }) {
            return (h, L("son seferlerde \(h)", "recently \(h)"))
        }
        if let label { return (comps.first?.runway ?? "", L("\(label.lowercased(with: Lang.locale)) için muhtemel", "likely for \(label.lowercased())")) }
        return (comps.first?.runway ?? "", L("rüzgâra göre muhtemel", "likely by wind"))
    }

    private func tag(for runway: String, pick: (runway: String, reason: String)) -> String? {
        if runway == pick.runway { return pick.reason }
        if runway == active { return L("aktif", "active") }
        return nil
    }

    /// Değer etiketi: "15 kt karşı" + hamle.
    private func label(_ value: Int, _ title: String, gust: Int?, color: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value) kt").font(.title3.bold())
                Text(title).font(.subheadline)
            }
            .foregroundStyle(color)
            if let gust, gust != value {
                Text(L("hamle", "gust") + " \(gust) kt").font(.caption).foregroundStyle(Palette.secondary)
            }
        }
        .fixedSize()
    }

    private func vArrow(down: Bool, length: CGFloat, color: Color) -> some View {
        VStack(spacing: 0) {
            if !down { Image(systemName: "arrowtriangle.up.fill").font(.system(size: 12)) }
            Rectangle().frame(width: 4, height: length)
            if down { Image(systemName: "arrowtriangle.down.fill").font(.system(size: 12)) }
        }
        .foregroundStyle(color)
    }

    private func hArrow(right: Bool, length: CGFloat) -> some View {
        HStack(spacing: 0) {
            if !right { Image(systemName: "arrowtriangle.left.fill").font(.system(size: 12)) }
            Rectangle().frame(width: length, height: 4)
            if right { Image(systemName: "arrowtriangle.right.fill").font(.system(size: 12)) }
        }
        .foregroundStyle(Palette.warn)
    }

    /// Pilot görünümü: pist yukarı doğru; oklar rüzgârın geldiği tarafta, pistin yanında.
    /// Yeşil (karşı) / kırmızı (arka) ok piste paralel, turuncu yan rüzgâr oku piste dik; değerler okların yanında.
    private func drawing(_ c: RunwayWind, maxSpeed: Int) -> some View {
        let scale = CGFloat(max(maxSpeed, 1))
        let headLen = max(16, CGFloat(abs(c.head)) / scale * 56)
        let crossLen = max(16, CGFloat(c.cross) / scale * 56)
        let headColor = c.head >= 0 ? Palette.outbound : Color.red
        let fromLeft = c.cross > 0 && c.crossFromLeft
        let crossTitle = L("yan", "cross") + " · " + (c.crossFromLeft ? L("soldan", "from left") : L("sağdan", "from right"))

        let headRow = HStack(spacing: 10) {
            if c.head == 0 {
                Text(L("karşı/arka rüzgâr yok", "no head/tailwind")).font(.subheadline).foregroundStyle(Palette.secondary)
            } else {
                let arrow = vArrow(down: c.head > 0, length: headLen, color: headColor)
                let text = label(abs(c.head), c.head > 0 ? L("karşı", "head") : L("arka", "tail"),
                                 gust: c.gustHead.map { abs($0) }, color: headColor, trailing: fromLeft)
                if fromLeft { text; arrow } else { arrow; text }
            }
        }
        let crossRow = HStack(spacing: 8) {
            if c.cross == 0 {
                Text(L("yan rüzgâr yok", "no crosswind")).font(.subheadline).foregroundStyle(Palette.secondary)
            } else {
                let text = label(c.cross, crossTitle, gust: c.gustCross, color: Palette.warn, trailing: fromLeft)
                if fromLeft { text; hArrow(right: true, length: crossLen) } else { hArrow(right: false, length: crossLen); text }
            }
        }
        let side = VStack(alignment: fromLeft ? .trailing : .leading, spacing: 18) {
            headRow
            crossRow
        }
        let runway = ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.24))
            Rectangle().fill(Color.white.opacity(0.6)).frame(width: 2).padding(.vertical, 16)
                .mask(VStack(spacing: 6) { ForEach(0..<9, id: \.self) { _ in Rectangle().frame(height: 6) } })
            VStack {
                Spacer()
                Text(c.runway).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white).padding(.bottom, 3)
            }
        }
        .frame(width: 26, height: 130)

        return HStack(spacing: 12) {
            if fromLeft { side; runway } else { runway; side }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Pist \(c.runway): \(c.head >= 0 ? "karşı" : "arka") \(abs(c.head)) knot, yan \(c.cross) knot \(c.crossFromLeft ? "soldan" : "sağdan")", "Runway \(c.runway): \(c.head >= 0 ? "headwind" : "tailwind") \(abs(c.head)) knots, crosswind \(c.cross) knots from the \(c.crossFromLeft ? "left" : "right")"))
    }

}
