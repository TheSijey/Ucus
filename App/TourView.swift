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
                        Picker(L("Saat", "Time"), selection: $showUTC) {
                            Text(L("Yerel saat", "Local time")).tag(false)
                            Text("UTC").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 18)

                        if let ib = s.freshInbound { inboundStep(ib) }
                        if s.isOutstation, let p = s.pickupAt { pickupStep(s, p) }
                        signOnStep(s)
                        outboundStep(s)
                        if !s.isOutstation { destinationStep(s) }
                        if let t = s.turn, t.returnFlight != nil { returnStep(t) }
                        endStep(s)
                    }
                    .padding(16)
                } else {
                    EmptyFlightView().padding(.top, 60)
                }
            }
            .background(Palette.bg)
            .navigationTitle(L("Tur", "Trip"))
            .toolbar { CommonToolbar() }
            .refreshable { await model.refresh() }
        }
    }

    private func t(_ d: Date?) -> String { showUTC ? FlightHelpers.utc(d) : FlightHelpers.hm(d) }

    // MARK: Adımlar

    private func inboundStep(_ ib: InboundInfo) -> some View {
        Step(dot: .hollow(Palette.secondary), line: .thin) {
            Text(L("Uçak geliyor", "Inbound aircraft") + " · \([ib.flight, ib.fromCode].filter { !$0.isEmpty }.joined(separator: " "))")
                .font(.caption).foregroundStyle(Palette.secondary)
            if let parked = ib.parked {
                HStack(spacing: 4) {
                    Text(L("Park", "Parked") + " \(ib.approx)\(showUTC ? t(parked) : DayClock.text(parked)) ·").font(.headline)
                    MinutesAgo(date: parked).font(.headline)
                }
                if ib.isAssumed == true {
                    Text(L("Gerçek iniş/park saati yayınlanmadı; tahmini saate göre gösteriliyor.", "Actual landing/on-block time not published; shown from the estimate."))
                        .font(.caption2).foregroundStyle(Palette.secondary)
                }
            } else if let landed = ib.landed {
                Text(L("İndi \(t(landed)) · parkta ~\(t(ib.estimatedPark))", "Landed \(t(landed)) · on stand ~\(t(ib.estimatedPark))")).font(.headline)
            } else {
                Text(L("Tahmini iniş \(t(ib.estimatedLanding)) · parkta ~\(t(ib.estimatedPark))", "Est. landing \(t(ib.estimatedLanding)) · on stand ~\(t(ib.estimatedPark))")).font(.headline)
            }
            HStack(spacing: 10) {
                if let tm = ib.taxiMinutes {
                    Text(L("Taksi tahmini \(tm) dk", "Taxi est. \(tm) min") + ((ib.taxiSamples ?? 0) > 0 ? L(" (\(ib.taxiSamples!) ölçüm)", " (\(ib.taxiSamples!) samples)") : ""))
                }
                if let rwy = ib.landingRunway, !rwy.isEmpty { Text(L("İniş pisti", "Landing rwy") + " \(rwy)") }
            }
            .font(.footnote).foregroundStyle(.white.opacity(0.75))
        }
    }

    /// Dış meydan: meydanın yerel saati ("06:30 BEY yerel").
    private func stationLocal(_ s: FlightAttributes.ContentState, _ d: Date?) -> String {
        guard let d else { return "" }
        return L("\(FlightHelpers.local(d, s.originTimeZone)) \(s.originCode) yerel", "\(FlightHelpers.local(d, s.originTimeZone)) \(s.originCode) local")
    }

    private func pickupStep(_ s: FlightAttributes.ContentState, _ p: Date) -> some View {
        Step(dot: .filled(Palette.outbound), line: .thin) {
            Text(L("Otelden çıkış", "Hotel pickup") + " · \(s.originCity ?? s.originCode)").font(.caption).foregroundStyle(Palette.secondary)
            Text(t(p)).font(.title3.bold())
            Text(stationLocal(s, p)).font(.footnote).foregroundStyle(.white.opacity(0.75))
        }
    }

    private func signOnStep(_ s: FlightAttributes.ContentState) -> some View {
        Step(dot: .filled(Palette.signOn), line: .thin) {
            if s.isOutstation {
                Text(L("İmza", "Sign-on") + " · \(s.originCity ?? s.originCode)").font(.caption).foregroundStyle(Palette.secondary)
                Text((s.signOnManual == true ? "" : "~") + t(s.signOn)).font(.title3.bold())
                VStack(alignment: .leading, spacing: 2) {
                    Text(stationLocal(s, s.signOn) + (s.signOnManual == true ? "" : L(" · tahmini (Bugün'den gir)", " · estimate (set it in Today)")))
                    Text("STD \(t(s.eobt))")
                }
                .font(.footnote).foregroundStyle(.white.opacity(0.75))
            } else {
                Text(L("İmza · İstanbul", "Sign-on · Istanbul")).font(.caption).foregroundStyle(Palette.secondary)
                Text(t(s.signOn)).font(.title3.bold())
                VStack(alignment: .leading, spacing: 2) {
                    if let leave = s.leaveAt { Text(L("Evden çıkış", "Leave home") + " \(t(leave))") }
                    Text("EOBT \(t(s.eobt)) · TOBT \(t(s.tobt))")
                    if s.tsat != nil || s.ctot != nil { Text("TSAT \(t(s.tsat)) · CTOT \(t(s.ctot))") }
                }
                .font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func outboundStep(_ s: FlightAttributes.ContentState) -> some View {
        let dep = s.tsat ?? s.tobt ?? s.eobt
        let dest = s.turn.map { $0.destIATA.isEmpty ? $0.destICAO : $0.destIATA } ?? s.destination
        return Step(dot: .filled(Palette.outbound), line: .thick(Palette.outbound)) {
            Text(L("Gidiş", "Outbound") + " · \(s.flight)").font(.caption).foregroundStyle(Palette.outbound)
            Text("\(s.originCode) \(t(dep)) → \(Display.text(dest)) \(t(s.turn?.outboundArrival))").font(.title3.bold())
            HStack(spacing: 8) {
                Tile(title: "Stand", value: s.stand, color: Palette.stand)
                if s.isOutstation { Tile(title: "Gate", value: s.gate) } else { Tile(title: L("Pist", "Runway"), value: s.runway) }
                Tile(title: L("Süre", "Block"), value: FlightHelpers.duration(dep, s.turn?.outboundArrival) ?? "")
            }
        }
    }

    @ViewBuilder
    private func destinationStep(_ s: FlightAttributes.ContentState) -> some View {
        if let tr = s.turn {
            let gate = FlightHelpers.destGate(tr)
            Step(dot: .hollow(Palette.secondary), line: .thin) {
                Text([tr.destCity.isEmpty ? tr.destICAO : tr.destCity,
                      FlightHelpers.duration(tr.outboundArrival, tr.returnDeparture).map { L("tur", "turnaround") + " \($0)" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Palette.secondary)
                let code = tr.destIATA.isEmpty ? tr.destICAO : tr.destIATA
                if let gate {
                    Text(L("Yolcu kapısı", "Passenger gate") + " \(gate.isEstimate ? "~" : "")\(gate.gate) (" + L("\(code) yayını", "published by \(code)") + ")")
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                    if !tr.destGateHistory.isEmpty {
                        Text(L("Son günler: ", "Recent days: ") + tr.destGateHistory.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Palette.secondary.opacity(0.8))
                    }
                    Text(L("Park standı değildir; uçak uzak bir standda olabilir.", "Not the parking stand; the aircraft may be on a remote stand."))
                        .font(.caption2).foregroundStyle(Palette.secondary.opacity(0.7))
                } else {
                    Text(L("Yolcu kapısı bilgisi yok", "No passenger gate info")).font(.subheadline).foregroundStyle(Palette.secondary)
                }
            }
        } else if !s.destination.isEmpty {
            Step(dot: .hollow(Palette.secondary), line: .thin) {
                Text(AirportDB.city(s.destination) ?? s.destination).font(.caption).foregroundStyle(Palette.secondary)
                Text(AeroDataBox.quotaBlocked
                     ? L("Varış ve dönüş saatleri şu an alınamıyor: AeroDataBox aylık kotası doldu.", "Arrival and return times unavailable: AeroDataBox monthly quota reached.")
                     : L("Varış ve dönüş bilgisi bulunamadı.", "No arrival/return info found."))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
            }
        }
    }

    private func returnStep(_ tr: TurnInfo) -> some View {
        let dest = tr.destIATA.isEmpty ? tr.destICAO : tr.destIATA
        return Step(dot: .filled(Palette.ret), line: .thick(Palette.ret)) {
            Text(L("Dönüş", "Return") + " · \(tr.returnFlight ?? "")").font(.caption).foregroundStyle(Color(red: 0.6, green: 0.79, blue: 1))
            Text("\(dest) \(t(tr.returnDeparture)) → IST \(t(tr.returnArrival))").font(.title3.bold())
            if let d = FlightHelpers.duration(tr.returnDeparture, tr.returnArrival) {
                Text(L("Süre", "Block") + " \(d)").font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func endStep(_ s: FlightAttributes.ContentState) -> some View {
        Step(dot: .filled(.white), line: .none) {
            let endCity = s.isOneWay ? (s.turn.map { $0.destCity.isEmpty ? $0.destIATA : $0.destCity } ?? s.destination) : "İstanbul"
            Text(L("Görev sonu", "Duty end") + " · \(endCity)" + (s.isOneWay && !s.isOutstation ? L(" (yatılı)", " (layover)") : ""))
                .font(.caption).foregroundStyle(Palette.secondary)
            Text(t(s.turn?.returnArrival ?? s.turn?.outboundArrival)).font(.title3.bold())
            if let total = FlightHelpers.duration(s.signOn, s.turn?.returnArrival ?? s.turn?.outboundArrival) {
                Text(L("İmzadan itibaren", "Since sign-on") + " \(total)").font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
            Text(s.isOneWay
                 ? L("Uçuş, uygulamada ve kilit ekranında inişten 30 dk sonrasına kadar kalır (Ada'dan imza + 30 dk'da kalkar).", "The flight stays in the app and on the Lock Screen until 30 min after landing (leaves the Dynamic Island at sign-on + 30 min).")
                 : L("Uçuş, uygulamada ve kilit ekranında bu saate kadar kalır (Ada'dan imza + 30 dk'da kalkar).", "The flight stays in the app and on the Lock Screen until this time (leaves the Dynamic Island at sign-on + 30 min)."))
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
