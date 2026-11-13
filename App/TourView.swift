import SwiftUI

/// Tur: günün akışı yukarıdan aşağı.
struct TourView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared
    @AppStorage("tourShowsUTC") private var showUTC = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = session.state {
                    VStack(alignment: .leading, spacing: 0) {
                        Picker("Saat", selection: $showUTC) {
                            Text("Yerel saat").tag(false)
                            Text("UTC").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 18)

                        if let ib = s.inbound { inboundStep(ib) }
                        signOnStep(s)
                        outboundStep(s)
                        destinationStep(s)
                        if let t = s.turn, t.returnFlight != nil { returnStep(t) }
                        endStep(s)
                    }
                    .padding(16)
                } else {
                    EmptyFlightView().padding(.top, 60)
                }
            }
            .background(Palette.bg)
            .navigationTitle("Tur")
            .toolbar { CommonToolbar() }
            .refreshable { await model.refresh() }
        }
    }

    private func t(_ d: Date?) -> String { showUTC ? FlightHelpers.utc(d) : FlightHelpers.hm(d) }

    // MARK: Adımlar

    private func inboundStep(_ ib: InboundInfo) -> some View {
        Step(dot: .hollow(Palette.secondary), line: .thin) {
            Text("Uçak geliyor · \([ib.flight, ib.fromCode].filter { !$0.isEmpty }.joined(separator: " "))")
                .font(.caption).foregroundStyle(Palette.secondary)
            if let parked = ib.parked {
                HStack(spacing: 4) {
                    Text("Park \(ib.approx)\(showUTC ? t(parked) : DayClock.text(parked)) ·").font(.headline)
                    MinutesAgo(date: parked).font(.headline)
                }
                if ib.isAssumed == true {
                    Text("Gerçek iniş/park saati yayınlanmadı; tahmini saate göre gösteriliyor.")
                        .font(.caption2).foregroundStyle(Palette.secondary)
                }
            } else if let landed = ib.landed {
                Text("İndi \(t(landed)) · parkta ~\(t(ib.estimatedPark))").font(.headline)
            } else {
                Text("Tahmini iniş \(t(ib.estimatedLanding)) · parkta ~\(t(ib.estimatedPark))").font(.headline)
            }
            HStack(spacing: 10) {
                if let tm = ib.taxiMinutes {
                    Text("Taksi tahmini \(tm) dk" + ((ib.taxiSamples ?? 0) > 0 ? " (\(ib.taxiSamples!) ölçüm)" : ""))
                }
                if let rwy = ib.landingRunway, !rwy.isEmpty { Text("İniş pisti \(rwy)") }
            }
            .font(.footnote).foregroundStyle(.white.opacity(0.75))
        }
    }

    private func signOnStep(_ s: FlightAttributes.ContentState) -> some View {
        Step(dot: .filled(Palette.signOn), line: .thin) {
            Text("İmza · İstanbul").font(.caption).foregroundStyle(Palette.secondary)
            Text(t(s.signOn)).font(.title3.bold())
            VStack(alignment: .leading, spacing: 2) {
                if let leave = s.leaveAt { Text("Evden çıkış \(t(leave))") }
                Text("EOBT \(t(s.eobt)) · TOBT \(t(s.tobt))")
                if s.tsat != nil || s.ctot != nil { Text("TSAT \(t(s.tsat)) · CTOT \(t(s.ctot))") }
            }
            .font(.footnote).foregroundStyle(.white.opacity(0.75))
        }
    }

    private func outboundStep(_ s: FlightAttributes.ContentState) -> some View {
        let dep = s.tsat ?? s.tobt ?? s.eobt
        let dest = s.turn.map { $0.destIATA.isEmpty ? $0.destICAO : $0.destIATA } ?? s.destination
        return Step(dot: .filled(Palette.outbound), line: .thick(Palette.outbound)) {
            Text("Gidiş · \(s.flight)").font(.caption).foregroundStyle(Palette.outbound)
            Text("IST \(t(dep)) → \(Display.text(dest)) \(t(s.turn?.outboundArrival))").font(.title3.bold())
            HStack(spacing: 8) {
                Tile(title: "Stand", value: s.stand, color: Palette.stand)
                Tile(title: "Pist", value: s.runway)
                Tile(title: "Süre", value: FlightHelpers.duration(dep, s.turn?.outboundArrival) ?? "")
            }
        }
    }

    @ViewBuilder
    private func destinationStep(_ s: FlightAttributes.ContentState) -> some View {
        if let tr = s.turn {
            let gate = FlightHelpers.destGate(tr)
            Step(dot: .hollow(Palette.secondary), line: .thin) {
                Text([tr.destCity.isEmpty ? tr.destICAO : tr.destCity,
                      FlightHelpers.duration(tr.outboundArrival, tr.returnDeparture).map { "tur \($0)" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Palette.secondary)
                if let gate {
                    Text(gate.isEstimate ? "Gate ~\(gate.gate) (tahmini)" : "Gate \(gate.gate)")
                        .font(.title3.bold()).foregroundStyle(Palette.stand)
                } else {
                    Text("Gate bilgisi yok").font(.headline).foregroundStyle(Palette.secondary)
                }
                if !tr.destGateHistory.isEmpty {
                    Text("Son günler: " + tr.destGateHistory.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }

    private func returnStep(_ tr: TurnInfo) -> some View {
        let dest = tr.destIATA.isEmpty ? tr.destICAO : tr.destIATA
        return Step(dot: .filled(Palette.ret), line: .thick(Palette.ret)) {
            Text("Dönüş · \(tr.returnFlight ?? "")").font(.caption).foregroundStyle(Color(red: 0.6, green: 0.79, blue: 1))
            Text("\(dest) \(t(tr.returnDeparture)) → IST \(t(tr.returnArrival))").font(.title3.bold())
            if let d = FlightHelpers.duration(tr.returnDeparture, tr.returnArrival) {
                Text("Süre \(d)").font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func endStep(_ s: FlightAttributes.ContentState) -> some View {
        Step(dot: .filled(.white), line: .none) {
            Text("Görev sonu · İstanbul").font(.caption).foregroundStyle(Palette.secondary)
            Text(t(s.turn?.returnArrival ?? s.turn?.outboundArrival)).font(.title3.bold())
            if let total = FlightHelpers.duration(s.signOn, s.turn?.returnArrival) {
                Text("İmzadan itibaren \(total)").font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
            Text("Uçuş, uygulamada ve kilit ekranında bu saate kadar kalır (Ada'dan imza + 30 dk'da kalkar).")
                .font(.caption2).foregroundStyle(Palette.secondary).padding(.top, 4)
        }
    }
}

/// Dikey akıştaki bir adım: solda nokta ve çizgi, sağda içerik.
struct Step<Content: View>: View {
    enum Dot { case filled(Color), hollow(Color) }
    enum Line { case none, thin, thick(Color) }
    let dot: Dot
    let line: Line
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                switch dot {
                case .filled(let c): Circle().fill(c).frame(width: 14, height: 14)
                case .hollow(let c): Circle().strokeBorder(c, lineWidth: 3).frame(width: 14, height: 14)
                }
                switch line {
                case .none: EmptyView()
                case .thin: Rectangle().fill(Color.white.opacity(0.15)).frame(width: 2).frame(maxHeight: .infinity)
                case .thick(let c): Rectangle().fill(c).frame(width: 4).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)
            .padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 22)
        }
        .foregroundStyle(.white)
    }
}
