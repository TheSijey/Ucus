import SwiftUI

/// Bugün: en sık bakılan bilgiler büyük.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared
    @State private var weather: [AirportWeather] = []
    @State private var editing: ManualField?
    @State private var showTimesHelp = false
    @ObservedObject private var notams = NotamStore.shared
    @ObservedObject private var briefing = BriefingStore.shared

    enum ManualField: String, Identifiable { case pickup, signOn, stand; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = session.state {
                    VStack(spacing: 12) {
                        PhaseBar(state: s)
                        phaseCard(s)
                        standCard(s)
                        if s.isOutstation { manualCard(s) }
                        weatherStrip(s)
                        briefingRow(s)
                        tiles(s)
                        inboundRow(s)
                        NavigationLink { TourScreen() } label: { scheduleRow(s) }
                            .buttonStyle(.plain)
                        messages
                        footer(s)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .task(id: s.updatedAt) {
                        weather = await WeatherService.fetch(FlightHelpers.airports(s))
                    }
                } else {
                    VStack {
                        messages.padding(.horizontal, 16)
                        EmptyFlightView()
                    }
                    .padding(.top, 60)
                }
            }
            .background(Palette.bg)
            .navigationTitle(L("Bugün", "Today"))
            .toolbar { CommonToolbar() }
            .refreshable { await model.refresh() }
            .alert(L("Kalkış saatleri", "Departure times"), isPresented: $showTimesHelp) {
                Button(L("Tamam", "OK"), role: .cancel) {}
            } message: {
                Text(L("Planlanan (TOBT): uçağın hazır olacağı saat.\nPush izni (TSAT): itme/çalıştırma onayının beklendiği saat.\nSlot (CTOT): Eurocontrol'ün verdiği kalkış saati; yoksa slot yok.",
                       "Planned (TOBT): when the aircraft will be ready.\nPush approval (TSAT): expected start-up/push time.\nSlot (CTOT): Eurocontrol take-off time; empty means no slot."))
            }
            .sheet(item: $editing) { field in
                if let s = session.state { ManualEditSheet(state: s, field: field).environmentObject(model) }
            }
        }
    }

    // MARK: Sade üst bölüm (2.4)

    /// Aşamanın tek sorusu: evdeyken çıkışa, sonra imzaya, sonra sıradaki ana kalan süre.
    private func phaseCard(_ s: FlightAttributes.ContentState) -> some View {
        let leave = s.upcomingLeave()
        let next = nextEvent(s)
        let title = leave != nil ? (s.isOutstation ? L("Otelden çıkmana", "Hotel pickup in") : L("Evden çıkmana", "Leave home in")) : next.title
        let target = leave ?? next.date
        let color = leave != nil ? Palette.outbound : next.color
        let sub: String = {
            if let leave {
                let tz = s.isOutstation ? s.originTimeZone : TimeZone.current
                return L("Çıkış \(FlightHelpers.local(leave, tz)) · İmza \(FlightHelpers.local(s.signOn, tz))", "Leave \(FlightHelpers.local(leave, tz)) · Sign-on \(FlightHelpers.local(s.signOn, tz))")
            }
            return (s.isOutstation ? "\(s.flight) \(s.originCode) → " : "\(s.flight) → ") + Display.text(s.destCode) + (s.turn?.destCity.isEmpty == false ? " · \(s.turn!.destCity)" : "")
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold()).foregroundStyle(color.opacity(0.9))
            Countdown(target: target).font(.system(size: 52, weight: .heavy)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.subheadline).foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(color.opacity(0.3)))
    }

    /// Stand büyük.
    private func standCard(_ s: FlightAttributes.ContentState) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("STAND").font(.caption2.bold()).tracking(1).foregroundStyle(Palette.secondary)
                Text(Display.text(s.stand)).font(.system(size: 46, weight: .heavy)).foregroundStyle(Palette.stand)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text([s.registration, s.aircraftType].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// İki meydanın havası tek satır; dokununca Hava sekmesi.
    @ViewBuilder
    private func weatherStrip(_ s: FlightAttributes.ContentState) -> some View {
        if !weather.isEmpty {
            Button { model.tab = .weather } label: {
                HStack(spacing: 10) {
                    ForEach(Array(weather.enumerated()), id: \.element.icao) { i, w in
                        if i > 0 { Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 20) }
                        let st = WeatherStatus(w)
                        HStack(spacing: 5) {
                            Image(systemName: st.icon).foregroundStyle(st.color)
                            Text("\(WeatherStatus.city(w.icao, s)) \(st.short)")
                                .font(.subheadline.weight(st.isWarning ? .bold : .regular))
                                .foregroundStyle(st.isWarning ? Color(red: 1, green: 0.76, blue: 0.4) : .white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Hava sekmesini açar", "Opens the Weather tab"))
        }
    }

    /// Brifing'de bakılacaklar.
    private func briefingRow(_ s: FlightAttributes.ContentState) -> some View {
        let key = BriefingStore.key(for: s)
        let critical = (notams.packages[key].map { NotamFilter.relevant($0.notams, s) } ?? []).filter { $0.level == .critical }.count
        let defects = briefing.notes(key).defects.count
        var parts: [String] = []
        if critical > 0 { parts.append(L("\(critical) kritik NOTAM", "\(critical) critical NOTAMs")) }
        if defects > 0 { parts.append(L("\(defects) kabin arızası", "\(defects) cabin defects")) }
        if notams.packages[key] == nil { parts.append(L("NOTAM eklenmedi", "No NOTAMs yet")) }
        let warn = critical > 0
        return Button { model.tab = .briefing } label: {
            HStack(spacing: 14) {
                Image(systemName: warn ? "exclamationmark.triangle.fill" : "list.clipboard")
                    .font(.title3).foregroundStyle(warn ? Palette.warn : Palette.stand)
                    .frame(width: 40, height: 40)
                    .background((warn ? Palette.warn : Palette.stand).opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Brifing", "Briefing")).font(.headline)
                    Text(parts.isEmpty ? L("Hazır", "Ready") : parts.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
            }
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func scheduleRow(_ s: FlightAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Günün akışı", "Today's schedule")).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
            }
            if let tl = s.dayTimeline { DayTimelineBar(data: tl, height: 8, compactLegend: true) }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: Dış meydan: elle girilenler

    private func manualCard(_ s: FlightAttributes.ContentState) -> some View {
        Card(padding: 12) {
            VStack(spacing: 0) {
                manualRow(icon: "building.2.fill", color: Palette.outbound, title: L("Otelden çıkış", "Hotel pickup"),
                          value: s.pickupAt.map { FlightHelpers.local($0, s.originTimeZone) } ?? L("Gir", "Set"), field: .pickup)
                Divider().overlay(Color.white.opacity(0.08))
                manualRow(icon: "signature", color: Palette.signOn, title: L("İmza", "Sign-on"),
                          value: (s.signOnManual == true ? "" : "~") + FlightHelpers.local(s.signOn, s.originTimeZone)
                              + (s.signOnManual == true ? "" : L(" (tahmini, gir)", " (est., set)")), field: .signOn)
                Divider().overlay(Color.white.opacity(0.08))
                manualRow(icon: "parkingsign", color: Palette.stand, title: "Stand",
                          value: s.stand.isEmpty ? L("Gir", "Set") : s.stand, field: .stand)
                Text(L("Saatler \(s.originCity ?? s.originCode) yerel saatidir.", "Times are local to \(s.originCity ?? s.originCode)."))
                    .font(.caption2).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
        }
    }

    private func manualRow(icon: String, color: Color, title: String, value: String, field: ManualField) -> some View {
        Button { editing = field } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(color).frame(width: 22)
                Text(title).font(.subheadline)
                Spacer()
                Text(value).font(.subheadline.bold().monospacedDigit()).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Parçalar

    private func hero(_ s: FlightAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((s.isOutstation ? "\(s.flight) \(s.originCode) → " : "\(s.flight) → ") + (s.turn?.destIATA.isEmpty == false ? s.turn!.destIATA : Display.text(s.destination)))
                        .font(.title2.bold())
                    Text([s.registration, s.aircraftType, s.turn?.destCity ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("STAND").font(.caption2).tracking(1).foregroundStyle(Palette.secondary)
                    Text(Display.text(s.stand)).font(.system(size: 44, weight: .heavy)).foregroundStyle(Palette.stand)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            HStack(spacing: 10) {
                if let leave = s.upcomingLeave() {
                    counter(title: s.isOutstation ? L("Otelden çıkışa", "Hotel pickup") : L("Evden çıkışa", "Leave home"), target: leave, color: Palette.outbound)
                }
                let next = nextEvent(s)
                counter(title: next.title, target: next.date, color: next.color)
            }
            if let tl = s.dayTimeline {
                DayTimelineBar(data: tl, height: 8, compactLegend: true)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 0.075, green: 0.16, blue: 0.29), Palette.card],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.white)
    }

    private func counter(title: String, target: Date, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(color.opacity(0.85))
            Countdown(target: target).font(.title.bold()).foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Sıradaki önemli an: imza → kalkış → varış → dönüş kalkış → dönüş iniş.
    private func nextEvent(_ s: FlightAttributes.ContentState) -> (title: String, date: Date, color: Color) {
        let now = Date()
        let dep = s.tsat ?? s.tobt ?? s.eobt
        let steps: [(String, Date?, Color)] = [
            (L("İmzaya", "To sign-on") + " · \(FlightHelpers.hm(s.signOn))", s.signOn, Palette.signOn),
            (L("Kalkışa", "To departure") + " · \(FlightHelpers.hm(dep))", dep, Palette.outbound),
            (L("Varışa", "To arrival") + " · \(FlightHelpers.hm(s.turn?.outboundArrival))", s.turn?.outboundArrival, Palette.outbound),
            (L("Dönüş kalkışa", "To return departure") + " · \(FlightHelpers.hm(s.turn?.returnDeparture))", s.turn?.returnDeparture, Palette.ret),
            (L("İnişe", "To landing") + " · \(FlightHelpers.hm(s.turn?.returnArrival))", s.turn?.returnArrival, Palette.ret),
        ]
        for (t, d, c) in steps { if let d, d > now { return (t, d, c) } }
        return (L("İmza", "Sign-on") + " · \(FlightHelpers.hm(s.signOn))", s.signOn, Palette.signOn)
    }

    @ViewBuilder
    private var highlightsBanner: some View {
        let items = weather.flatMap { WeatherHighlights.scan(icao: $0.icao, metar: $0.metar, taf: $0.taf) }
        if !weather.isEmpty {
            Button { model.tab = .briefing } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: items.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(items.isEmpty ? Palette.outbound : Palette.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items.isEmpty ? L("Dikkat çeken bir durum yok", "Nothing notable") : L("\(items.count) önemli durum", "\(items.count) notable items"))
                            .font(.subheadline.bold())
                            .foregroundStyle(items.isEmpty ? Palette.outbound : Color(red: 1, green: 0.76, blue: 0.4))
                        if !items.isEmpty {
                            Text(items.prefix(2).joined(separator: " · "))
                                .font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
                }
                .padding(12)
                .background((items.isEmpty ? Palette.outbound : Palette.warn).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func tiles(_ s: FlightAttributes.ContentState) -> AnyView {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        let dest = s.turn.flatMap { FlightHelpers.destGate($0) }
        let destCode = s.turn.map { $0.destIATA.isEmpty ? $0.destICAO : $0.destIATA } ?? L("Varış", "Arrival")
        if s.isOutstation {
            return AnyView(LazyVGrid(columns: cols, spacing: 8) {
                Tile(title: "Gate", value: s.gate)
                Tile(title: L("Pist", "Runway"), value: s.runway)
                Tile(title: L("Kalkış", "Departure"), value: s.eobt.map { FlightHelpers.local($0, s.originTimeZone) } ?? "")
                Tile(title: L("Varış", "Arrival"), value: s.turn?.outboundArrival.map { FlightHelpers.hm($0) } ?? "")
                Tile(title: L("Süre", "Block"), value: FlightHelpers.duration(s.eobt, s.turn?.outboundArrival) ?? "")
                Tile(title: L("Tescil", "Reg"), value: s.registration)
            }
            )
        }
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Kalkış saatleri", "Departure times")).font(.headline)
                Spacer()
                Button(L("Bunlar ne?", "What are these?")) { showTimesHelp = true }.font(.subheadline)
            }
            LazyVGrid(columns: cols, spacing: 8) {
                Tile(title: L("Planlanan", "Planned") + " (TOBT)", value: s.tobt.map { FlightHelpers.hm($0) } ?? "")
                Tile(title: L("Push izni", "Push") + " (TSAT)", value: s.tsat.map { FlightHelpers.hm($0) } ?? "")
                Tile(title: L("Slot", "Slot") + " (CTOT)", value: s.ctot.map { FlightHelpers.hm($0) } ?? L("Yok", "None"))
                Tile(title: "Gate", value: s.gate)
                Tile(title: L("Pist", "Runway"), value: s.runway)
                Tile(title: "\(destCode) " + L("kapı", "gate"), value: dest.map { $0.isEstimate ? "~\($0.gate)" : $0.gate } ?? "")
            }
        })
    }

    @ViewBuilder
    private func inboundRow(_ s: FlightAttributes.ContentState) -> some View {
        if s.freshInbound != nil || FlightHelpers.fr24URL(s) != nil {
            Card(padding: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "airplane.arrival").font(.title3).foregroundStyle(Palette.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        if let ib = s.freshInbound {
                            Text(L("Gelen uçak", "Inbound") + " · \(Display.text(ib.fromCode))").font(.subheadline.bold())
                            inboundSubtitle(ib).font(.caption).foregroundStyle(Palette.secondary)
                        } else {
                            Text(L("Uçak", "Aircraft") + " \(Display.text(s.registration))").font(.subheadline.bold())
                            Text(L("Geliş bilgisi yok", "No inbound info")).font(.caption).foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    if let url = FlightHelpers.fr24URL(s) {
                        Button { FR24.open(url, flight: s.freshInbound?.flight) } label: {
                            Text("FR24").font(.footnote.bold())
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityLabel(L("Flightradar24'te aç", "Open in Flightradar24"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inboundSubtitle(_ ib: InboundInfo) -> some View {
        if let parked = ib.parked {
            HStack(spacing: 4) {
                Text(L("Park", "Parked") + " \(ib.approx)\(DayClock.text(parked)) ·")
                MinutesAgo(date: parked)
            }
        } else if let landed = ib.landed {
            Text(L("İndi \(FlightHelpers.hm(landed)) · parkta ~\(FlightHelpers.hm(ib.estimatedPark))", "Landed \(FlightHelpers.hm(landed)) · on stand ~\(FlightHelpers.hm(ib.estimatedPark))"))
        } else {
            Text(L("Tahmini iniş \(FlightHelpers.hm(ib.estimatedLanding)) · parkta ~\(FlightHelpers.hm(ib.estimatedPark))", "Est. landing \(FlightHelpers.hm(ib.estimatedLanding)) · on stand ~\(FlightHelpers.hm(ib.estimatedPark))"))
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let e = model.error {
            Text(e).font(.footnote).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let n = model.refreshNote {
            Text(n).font(.footnote).foregroundStyle(n.hasPrefix("✓") ? Palette.outbound : .red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(_ s: FlightAttributes.ContentState) -> some View {
        VStack(spacing: 10) {
            Text(L("Son güncelleme \(s.updatedAt.formatted(.dateTime.hour().minute().second())) · yenilemek için aşağı çek", "Last update \(s.updatedAt.formatted(.dateTime.hour().minute().second())) · pull down to refresh"))
                .font(.caption).foregroundStyle(Palette.secondary)
            Button(role: .destructive) {
                Task { await model.remove() }
            } label: {
                Text(L("Uçuşu kaldır", "Remove flight")).font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }
}

/// Günün aşamaları: Ev/Otel → Yol → İmza → Uçuş → Dönüş.
struct PhaseBar: View {
    let state: FlightAttributes.ContentState

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let steps = Self.steps(state)
            let current = Self.current(state, now: ctx.date, count: steps.count)
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(i < current ? Palette.outbound.opacity(0.45) : i == current ? color(i) : Color.white.opacity(0.12))
                            .frame(height: 4)
                        Text(steps[i]).font(.caption2.weight(i == current ? .bold : .regular))
                            .foregroundStyle(i == current ? color(i) : Palette.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Aşama: ", "Phase: ") + (steps.indices.contains(current) ? steps[current] : ""))
        }
    }

    private func color(_ i: Int) -> Color { i <= 1 ? Palette.outbound : i == 2 ? Palette.signOn : Palette.stand }

    static func steps(_ s: FlightAttributes.ContentState) -> [String] {
        var l = [s.isOutstation ? L("Otel", "Hotel") : L("Ev", "Home"), L("Yol", "Commute"), L("İmza", "Sign-on"), L("Uçuş", "Flight")]
        if s.turn?.returnFlight != nil { l.append(L("Dönüş", "Return")) }
        return l
    }

    static func current(_ s: FlightAttributes.ContentState, now: Date, count: Int) -> Int {
        if let leave = s.leaveAt, now < leave { return 0 }
        if now < s.signOn { return 1 }
        if let dep = s.departureTime, now < dep { return 2 }
        if let arr = s.turn?.outboundArrival, now < arr { return 3 }
        if count > 4 { return 4 }
        return 3
    }
}

/// Meydan havasının kısa durumu.
struct WeatherStatus {
    let short: String
    let icon: String
    let color: Color
    let isWarning: Bool
    let detail: String

    init(_ w: AirportWeather) {
        let hl = WeatherHighlights.scan(icao: w.icao, metar: w.metar, taf: w.taf)
        let sum = w.metar.map(MetarSummary.init)
        if hl.isEmpty {
            isWarning = false
            short = L("sorun yok", "fine")
            icon = "checkmark.circle.fill"
            color = Palette.outbound
        } else {
            isWarning = true
            let first = hl[0].components(separatedBy: ": ").dropFirst().joined(separator: ": ")
            short = first.isEmpty ? L("dikkat", "caution") : first
            icon = "exclamationmark.triangle.fill"
            color = Palette.warn
        }
        detail = [sum?.wind, sum?.visibility].compactMap { $0 }.filter { $0 != "—" }.joined(separator: " · ")
    }

    static func city(_ icao: String, _ s: FlightAttributes.ContentState) -> String {
        if icao == "LTFM" { return "İstanbul" }
        if icao == s.origin, let c = s.originCity, !c.isEmpty { return c }
        if let t = s.turn, t.destICAO == icao, !t.destCity.isEmpty { return t.destCity }
        return AirportDB.city(icao: icao) ?? icao
    }
}
