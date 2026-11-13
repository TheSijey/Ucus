import SwiftUI

/// Bugün: en sık bakılan bilgiler büyük.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared
    @State private var weather: [AirportWeather] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = session.state {
                    VStack(spacing: 12) {
                        hero(s)
                        highlightsBanner
                        tiles(s)
                        inboundRow(s)
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
            .navigationTitle("Bugün")
            .toolbar { CommonToolbar() }
            .refreshable { await model.refresh() }
        }
    }

    // MARK: Parçalar

    private func hero(_ s: FlightAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(s.flight) → \(s.turn?.destIATA.isEmpty == false ? s.turn!.destIATA : Display.text(s.destination))")
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
                    counter(title: "Evden çıkışa", target: leave, color: Palette.outbound)
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
            ("İmzaya · \(FlightHelpers.hm(s.signOn))", s.signOn, Palette.signOn),
            ("Kalkışa · \(FlightHelpers.hm(dep))", dep, Palette.outbound),
            ("Varışa · \(FlightHelpers.hm(s.turn?.outboundArrival))", s.turn?.outboundArrival, Palette.outbound),
            ("Dönüş kalkışa · \(FlightHelpers.hm(s.turn?.returnDeparture))", s.turn?.returnDeparture, Palette.ret),
            ("İnişe · \(FlightHelpers.hm(s.turn?.returnArrival))", s.turn?.returnArrival, Palette.ret),
        ]
        for (t, d, c) in steps { if let d, d > now { return (t, d, c) } }
        return ("İmza · \(FlightHelpers.hm(s.signOn))", s.signOn, Palette.signOn)
    }

    @ViewBuilder
    private var highlightsBanner: some View {
        let items = weather.flatMap { WeatherHighlights.scan(icao: $0.icao, metar: $0.metar, taf: $0.taf) }
        if !weather.isEmpty {
            Button { model.tab = .weather } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: items.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(items.isEmpty ? Palette.outbound : Palette.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items.isEmpty ? "Dikkat çeken bir durum yok" : "\(items.count) önemli durum")
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

    private func tiles(_ s: FlightAttributes.ContentState) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        let dest = s.turn.flatMap { FlightHelpers.destGate($0) }
        let destCode = s.turn.map { $0.destIATA.isEmpty ? $0.destICAO : $0.destIATA } ?? "Varış"
        return LazyVGrid(columns: cols, spacing: 8) {
            Tile(title: "Gate", value: s.gate)
            Tile(title: "Pist", value: s.runway)
            Tile(title: "TOBT", value: s.tobt.map { FlightHelpers.hm($0) } ?? "")
            Tile(title: "TSAT", value: s.tsat.map { FlightHelpers.hm($0) } ?? "")
            Tile(title: "CTOT", value: s.ctot.map { FlightHelpers.hm($0) } ?? "")
            Tile(title: "\(destCode) gate", value: dest.map { $0.isEstimate ? "~\($0.gate)" : $0.gate } ?? "",
                 color: Palette.stand)
        }
        .onTapGesture { model.tab = .tour }
    }

    @ViewBuilder
    private func inboundRow(_ s: FlightAttributes.ContentState) -> some View {
        if s.inbound != nil || FlightHelpers.fr24URL(s) != nil {
            Card(padding: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "airplane.arrival").font(.title3).foregroundStyle(Palette.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        if let ib = s.inbound {
                            Text("Gelen uçak · \(Display.text(ib.fromCode))").font(.subheadline.bold())
                            inboundSubtitle(ib).font(.caption).foregroundStyle(Palette.secondary)
                        } else {
                            Text("Uçak \(Display.text(s.registration))").font(.subheadline.bold())
                            Text("Geliş bilgisi yok").font(.caption).foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    if let url = FlightHelpers.fr24URL(s) {
                        Button { FR24.open(url, flight: s.inbound?.flight) } label: {
                            Text("FR24").font(.footnote.bold())
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityLabel("Flightradar24'te aç")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inboundSubtitle(_ ib: InboundInfo) -> some View {
        if let parked = ib.parked {
            HStack(spacing: 4) {
                Text("Park \(ib.approx)\(DayClock.text(parked)) ·")
                MinutesAgo(date: parked)
            }
        } else if let landed = ib.landed {
            Text("İndi \(FlightHelpers.hm(landed)) · parkta ~\(FlightHelpers.hm(ib.estimatedPark))")
        } else {
            Text("Tahmini iniş \(FlightHelpers.hm(ib.estimatedLanding)) · parkta ~\(FlightHelpers.hm(ib.estimatedPark))")
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
            Text("Son güncelleme \(s.updatedAt.formatted(.dateTime.hour().minute().second())) · yenilemek için aşağı çek")
                .font(.caption).foregroundStyle(Palette.secondary)
            Button(role: .destructive) {
                Task { await model.remove() }
            } label: {
                Text("Uçuşu kaldır").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }
}
