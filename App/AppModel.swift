import ActivityKit
import SwiftUI

enum AppTab: Hashable { case today, briefing, weather, airports, flights }

/// Sekmelerin ortak durumu ve işlemleri.
@MainActor
final class AppModel: ObservableObject {
    @Published var tab: AppTab = .today
    @Published var loading = false
    @Published var error: String?
    @Published var refreshNote: String?
    @Published var pending: PendingStart?
    @Published var showSettings = false
    @Published var showAdd = false
    @Published var recordRequest: RecordRequest?
    @Published var openAirport: String?   // başka sekmeden Meydanlar'da açılacak meydan

    let store = FlightStore()
    let session = FlightSession.shared
    private var startingPlanned: PlannedFlight?

    /// CDM başka bir günün uçuşunu gösterdiğinde onay için bekletilen başlatma.
    struct PendingStart: Identifiable {
        let id = UUID()
        let query: String
        let state: FlightAttributes.ContentState
        let message: String
    }

    // MARK: - Başlatma

    func start(planned f: PlannedFlight) async {
        startingPlanned = f
        await start(query: f.flight, plannedDay: f.date, legs: f.legNumbers)
    }

    func start(query raw: String, plannedDay: Date?, legs: [String]? = nil) async {
        AeroDataBox.clearQuotaBlock()
        if plannedDay == nil { startingPlanned = nil }
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let q = CDMFetcher.normalize(raw)
            let state = try await FlightLoader.load(query: raw, plannedDay: plannedDay, legs: legs)
            if let plannedDay {
                let departure = state.eobt ?? state.signOn.addingTimeInterval(CDMParser.signOnBeforeEOBT)
                let cal = UTC.calendar
                if !cal.isDate(departure, inSameDayAs: plannedDay), !cal.isDate(state.signOn, inSameDayAs: plannedDay) {
                    pending = PendingStart(
                        query: q, state: state,
                        message: L("CDM şu an \(state.flight) için \(UTCFormat.dayTime(departure)) UTC kalkışlı uçuşu gösteriyor. Bu senin \(UTCFormat.day(plannedDay)) (UTC) uçuşun olmayabilir; CDM o günün uçuşunu genelde aynı gün gösterir.", "CDM currently shows \(state.flight) departing \(UTCFormat.dayTime(departure)) UTC. This may not be your \(UTCFormat.day(plannedDay)) (UTC) flight; CDM usually shows a day's flight on that same day."))
                    return
                }
            }
            await begin(query: q, state: state)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func begin(query: String, state: FlightAttributes.ContentState) async {
        if state.tourEnd <= Date() {
            error = L("Bu uçuşun turu bitmiş görünüyor, eklenmedi.", "This flight's trip seems to be over; not added.")
            return
        }
        if state.hideAt > Date(), UIDevice.current.userInterfaceIdiom == .phone, !ActivityAuthorizationInfo().areActivitiesEnabled {
            error = L("Ayarlar > Uçuş > Canlı Etkinlikler'i aç.", "Turn on Settings > Uçuş > Live Activities.")
        }
        do {
            try await LiveActivityManager.start(query: query, state: state)
            if let p = startingPlanned, let s = session.state {
                FlightStore.markStarted(p, until: s.tourEnd)
            }
            refreshNote = nil
            tab = .today
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Yenile / kaldır

    func refresh() async {
        AeroDataBox.clearQuotaBlock()
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let oldSignOn = session.state?.signOn
        if let err = await FlightRefresher.refreshActive() {
            refreshNote = L("Yenilenemedi: \(err)", "Couldn't refresh: \(err)")
        } else {
            var note = "✓ " + L("Güncellendi", "Updated") + " \(Date().formatted(.dateTime.hour().minute()))"
            if let oldSignOn, let new = session.state?.signOn, new != oldSignOn {
                note += L(" · İmza \(new.formatted(.dateTime.hour().minute())) oldu", " · Sign-on now \(new.formatted(.dateTime.hour().minute()))")
            }
            refreshNote = note
        }
    }

    /// Dış meydan: elle girilen imza / otelden çıkış / stand kaydedilir ve takip güncellenir.
    func saveManual(_ e: ManualTimes.Entry) async {
        guard let s = session.state, s.isOutstation else { return }
        ManualTimes.save(e, for: s)
        var state = s
        if let so = e.signOn {
            state.signOn = so
            state.signOnManual = true
        } else {
            if let dep = s.eobt { state.signOn = dep.addingTimeInterval(-3600) }
            state.signOnManual = false
        }
        state.pickupAt = e.pickup
        state.stand = e.stand ?? ""
        do {
            try await LiveActivityManager.start(query: session.query, state: state)
        } catch {
            await LiveActivityManager.apply(state)
        }
    }

    func remove() async {
        await LiveActivityManager.endAll(reason: "Takibi bırak butonu")
        refreshNote = nil
    }

    /// İnişten sonra "Uçuşu bitir": takip kapanır, uçuş 24 saat "Son uçuşun" olarak Meydanlar'da kalır.
    func finishFlight() async {
        await LiveActivityManager.endAll(reason: "Uçuşu bitir")
        refreshNote = nil
    }
}

// MARK: - Ortak yardımcılar

enum FlightHelpers {
    /// Uçak havadaysa gelen seferin canlı takibi, değilse uçağın (tescil) sayfası.
    static func fr24URL(_ s: FlightAttributes.ContentState) -> URL? {
        if let ib = s.freshInbound, ib.parked == nil, ib.landed == nil, !ib.flight.isEmpty {
            return URL(string: "https://www.flightradar24.com/\(ib.flight.replacingOccurrences(of: " ", with: ""))")
        }
        guard !s.registration.isEmpty else { return nil }
        return URL(string: "https://www.flightradar24.com/data/aircraft/\(s.registration.lowercased())")
    }

    /// TAF'ta işaretlenecek saatler: İstanbul'da kalkış (yeşil) ve dönüş inişi (mavi),
    /// varışta iniş (yeşil) ve dönüş kalkışı (mavi).
    static func weatherEvents(_ s: FlightAttributes.ContentState) -> [String: [WeatherEvent]] {
        var ev: [String: [WeatherEvent]] = [:]
        if let o = s.origin {
            // Dış meydan → İstanbul: kalkış meydanında kalkış, İstanbul'da iniş
            if let dep = s.departureTime { ev[o] = [WeatherEvent(label: L("Kalkış", "Departure"), time: dep, isReturn: false)] }
            if let a = s.turn?.outboundArrival, let d = s.turn?.destICAO, !d.isEmpty {
                ev[d] = [WeatherEvent(label: L("İniş", "Landing"), time: a, isReturn: false)]
            }
            return ev
        }
        var ist: [WeatherEvent] = []
        if let dep = s.tsat ?? s.tobt ?? s.eobt { ist.append(WeatherEvent(label: L("Kalkış", "Departure"), time: dep, isReturn: false)) }
        if let t = s.turn {
            if let ra = t.returnArrival { ist.append(WeatherEvent(label: L("Dönüş iniş", "Return landing"), time: ra, isReturn: true)) }
            var dst: [WeatherEvent] = []
            if let a = t.outboundArrival { dst.append(WeatherEvent(label: L("İniş", "Landing"), time: a, isReturn: false)) }
            if let rd = t.returnDeparture { dst.append(WeatherEvent(label: L("Dönüş kalkış", "Return departure"), time: rd, isReturn: true)) }
            if !t.destICAO.isEmpty { ev[t.destICAO] = dst }
        }
        ev["LTFM"] = ist
        return ev
    }

    static func airports(_ s: FlightAttributes.ContentState) -> [String] {
        if let o = s.origin { return [o] + [destICAO(s)].compactMap { $0 }.filter { !$0.isEmpty && $0 != o } }
        return ["LTFM"] + [destICAO(s)].compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// Turun bütün meydanları (ara bacaklar dahil), sırayla.
    static func allAirports(_ s: FlightAttributes.ContentState) -> [String] {
        var list = airports(s)
        var codes: [String] = []
        if let r = s.turn?.returnToICAO { codes.append(r) }
        for leg in s.extraLegs ?? [] { codes.append(leg.fromICAO); codes.append(leg.toICAO) }
        for c in codes where !c.isEmpty && !list.contains(c) { list.append(c) }
        return list
    }

    /// Varış meydanı ICAO: dönüş bilgisinden, yoksa CDM'deki varış kodundan (BEY → OLBA).
    static func destICAO(_ s: FlightAttributes.ContentState) -> String? {
        if let d = s.turn?.destICAO, !d.isEmpty { return d }
        return AirportDB.icao(s.destination)
    }

    /// Varış meydanı gate'i: bugün yayınlandıysa o, değilse son günlerin en sık olanı (tahmin).
    static func destGate(_ t: TurnInfo) -> (gate: String, isEstimate: Bool)? {
        if let g = t.arrivalGateToday, !g.isEmpty { return (g, false) }
        if let g = t.destGateToday, !g.isEmpty { return (g, false) }
        if let g = mostCommon(t.destGateHistory) { return (g, true) }
        return nil
    }

    static func mostCommon(_ list: [String]) -> String? {
        guard !list.isEmpty else { return nil }
        let counts = Dictionary(list.map { ($0, 1) }, uniquingKeysWith: +)
        let best = counts.values.max() ?? 0
        return list.first { counts[$0] == best }
    }

    /// Meydanın yerel saatiyle "06:30".
    static func local(_ d: Date, _ tz: TimeZone) -> String {
        var st = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        st.timeZone = tz
        st.locale = Locale(identifier: "en_GB")
        return d.formatted(st)
    }

    static func hm(_ d: Date?) -> String { d.map { $0.formatted(.dateTime.hour().minute()) } ?? "—" }

    static func utc(_ d: Date?) -> String {
        guard let d else { return "—" }
        var st = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        st.timeZone = TimeZone(identifier: "UTC")!
        st.locale = Locale(identifier: "en_GB")
        return d.formatted(st) + "Z"
    }

    /// "4:40"
    static func duration(_ a: Date?, _ b: Date?) -> String? {
        guard let a, let b, b > a else { return nil }
        let m = Int(b.timeIntervalSince(a) / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

// MARK: - Ortak görünüm parçaları

enum Palette {
    static let bg = Color(red: 0.043, green: 0.059, blue: 0.09)
    static let card = Color(red: 0.086, green: 0.106, blue: 0.149)
    static let card2 = Color(red: 0.11, green: 0.133, blue: 0.188)
    static let secondary = Color(red: 0.604, green: 0.639, blue: 0.698)
    static let stand = Color(red: 0.353, green: 0.784, blue: 0.98)
    static let signOn = Color(red: 1.0, green: 0.839, blue: 0.039)
    static let outbound = Color(red: 0.188, green: 0.82, blue: 0.345)
    static let ret = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let warn = Color(red: 1.0, green: 0.624, blue: 0.039)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Tile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.secondary)
            Text(value.isEmpty ? "—" : value).font(.headline.monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyFlightView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "airplane.departure").font(.system(size: 44)).foregroundStyle(Palette.secondary)
            Text(L("Takip edilen uçuş yok", "No flight tracked")).font(.title3.bold())
            Text(L("Uçuşlarım'da bir uçuşa \"Takibi başlat\" de ya da sefer/tescil ara.", "Tap \"Start tracking\" on a flight in My Flights, or search a flight/registration."))
                .font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Button {
                model.tab = .flights
            } label: {
                Text(L("Uçuşlarım'a git", "Go to My Flights")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}
