import ActivityKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = FlightStore()
    @AppStorage(AppSettings.leaveMinutesKey) private var leaveMinutes = 60

    @State private var query = ""
    @State private var info: FlightAttributes.ContentState?
    @State private var loading = false
    @State private var error: String?
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var pending: PendingStart?
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var startingPlanned: PlannedFlight?
    @State private var refreshNote: String?
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool

    /// CDM başka bir günün uçuşunu gösterdiğinde onay için bekletilen başlatma.
    struct PendingStart: Identifiable {
        let id = UUID()
        let query: String
        let state: FlightAttributes.ContentState
        let message: String
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if let info {
                    activeSection(info)
                }

                Section {
                    if store.upcoming.isEmpty {
                        Text("Henüz uçuş yok. Sağ üstteki + ile ekle.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.upcoming) { f in
                        plannedRow(f)
                            .swipeActions {
                                Button("Sil", role: .destructive) { store.delete(f) }
                            }
                    }
                } header: {
                    Text("Uçuşlarım")
                } footer: {
                    if leaveMinutes > 0 {
                        Text("Ada'ya eklediğinde imzadan \(Display.minutes(leaveMinutes)) önce çıkış bildirimi kurulur.")
                    }
                }

                Section {
                    HStack {
                        TextField("Sefer (1751) ya da tescil (LTD)", text: $query)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit { Task { await start(query: query, plannedDay: nil) } }
                        if loading { ProgressView() }
                    }
                    Button {
                        Task { await start(query: query, plannedDay: nil) }
                    } label: {
                        Label("Getir ve Ada'ya koy", systemImage: "airplane.departure")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Hızlı arama")
                } footer: {
                    Text("Bilgi İGA CDM'den alınır. İmza = EOBT − 1:15, kaybolma imza + 30 dk.")
                }
            }
            .navigationTitle("Uçuş")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if info != nil {
                        Button { Task { await refresh() } } label: {
                            if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                        }
                        .disabled(loading)
                    }
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFlightView { date, flight in store.add(date: date, flight: flight) }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
                OnboardingView()
            }
            .alert("Tarih farklı", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("Yine de ekle") {
                    if let p = pending { Task { await begin(query: p.query, state: p.state) } }
                    pending = nil
                }
                Button("Vazgeç", role: .cancel) { pending = nil }
            } message: {
                Text(pending?.message ?? "")
            }
            .task {
                store.prune()
                loadCurrent()
                ActivityObserver.watchAll()
            }
            .refreshable { await refresh() }
            .onOpenURL { url in
                if url.scheme == "ucus", url.host == "refresh" {
                    Task { await refresh() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.prune()
                    loadCurrent()
                    ActivityObserver.watchAll()
                    if let info, Date().timeIntervalSince(info.updatedAt) > 180 {
                        Task { await refresh() }
                    }
                }
            }
        }
    }

    // MARK: - Bölümler

    @ViewBuilder
    private func activeSection(_ info: FlightAttributes.ContentState) -> some View {
        if let tl = info.dayTimeline {
            Section("Günün akışı (yerel)") {
                DayTimelineBar(data: tl)
                    .padding(.vertical, 4)
            }
        }
        Section("Ada'da") {
            row("Sefer", "\(info.flight)  →  \(Display.text(info.destination))")
            row("Tescil", "\(Display.text(info.registration))  ·  \(Display.text(info.aircraftType))")
            if let url = fr24URL(info) {
                Link(destination: url) {
                    Label("Flightradar24'te uçağı aç", systemImage: "location.fill.viewfinder")
                }
            }
            row("Stand", info.stand)
            row("Gate", info.gate)
            row("Pist", info.runway)
        }
        if let ib = info.inbound {
            Section("Gelen uçak") {
                row("Nereden", [ib.flight, ib.fromCode, ib.fromCity].filter { !$0.isEmpty }.joined(separator: " · "))
                if let url = fr24URL(info) {
                    Link(destination: url) {
                        Label(ib.parked == nil ? "Canlı konum (Flightradar24)" : "Flightradar24'te aç",
                              systemImage: "location.fill.viewfinder")
                            .font(.headline)
                    }
                }
                if let parked = ib.parked {
                    LabeledContent("Park etti") {
                        HStack(spacing: 4) {
                            Text("\(parked.formatted(.dateTime.hour().minute())) ·")
                            MinutesAgo(date: parked)
                        }
                    }
                } else {
                    if let landed = ib.landed {
                        timeRow("İndi", landed)
                    } else {
                        timeRow("Tahmini iniş", ib.estimatedLanding)
                    }
                    timeRow("Tahmini park", ib.estimatedPark)
                }
                if let rwy = ib.landingRunway, !rwy.isEmpty {
                    row("İniş pisti", rwy)
                }
                if let t = ib.taxiMinutes {
                    LabeledContent("Taksi tahmini") {
                        Text((ib.taxiSamples ?? 0) > 0 ? "\(t) dk (\(ib.taxiSamples!) ölçüm)" : "\(t) dk (genel)")
                    }
                }
            }
        }
        if let t = info.turn {
            Section("Tur (yerel saat)") {
                LabeledContent("Varış \(t.destIATA.isEmpty ? t.destICAO : t.destIATA)") {
                    if let a = t.outboundArrival {
                        Text(a, format: .dateTime.hour().minute()).monospacedDigit()
                    } else { Text("—") }
                }
                if let rf = t.returnFlight {
                    LabeledContent("Dönüş \(rf)") {
                        HStack(spacing: 4) {
                            if let d = t.returnDeparture { Text(d, format: .dateTime.hour().minute()) }
                            Image(systemName: "arrow.right").font(.caption2)
                            if let a = t.returnArrival { Text(a, format: .dateTime.hour().minute()) } else { Text("—") }
                        }
                        .monospacedDigit()
                    }
                    if let a = t.returnArrival {
                        LabeledContent("İstanbul'a iniş") {
                            Text(a, format: .dateTime.weekday(.abbreviated).hour().minute()).monospacedDigit()
                        }
                    }
                } else {
                    Text("Bu uçağın dönüş seferi henüz görünmüyor.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        WeatherSection(icaos: ["LTFM"] + [info.turn?.destICAO].compactMap { $0 }.filter { !$0.isEmpty },
                       reloadKey: info.updatedAt,
                       activeRunways: info.runway.isEmpty ? [:] : ["LTFM": info.runway],
                       events: weatherEvents(info))
        Section("Saatler (yerel)") {
            if let leave = info.upcomingLeave() {
                LabeledContent("Çıkışa kalan") {
                    Countdown(target: leave).font(.title3.bold()).foregroundStyle(.green)
                }
            }
            LabeledContent("İmzaya kalan") {
                Countdown(target: info.signOn).font(.title3.bold()).foregroundStyle(.orange)
            }
            timeRow("Evden çıkış", info.leaveAt)
            timeRow("İmza", info.signOn)
            timeRow("EOBT", info.eobt)
            timeRow("TOBT", info.tobt)
            timeRow("TSAT", info.tsat)
            timeRow("CTOT", info.ctot)
            timeRow("Kaybolma", info.hideAt)
        }
        Section {
            Button {
                Task { await refresh() }
            } label: {
                HStack {
                    Label("Yenile", systemImage: "arrow.clockwise")
                        .font(.headline)
                    Spacer()
                    if loading {
                        ProgressView()
                    } else {
                        Text("Son: \(info.updatedAt.formatted(.dateTime.hour().minute().second()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(loading)
            if let refreshNote {
                Text(refreshNote).font(.footnote).foregroundStyle(refreshNote.hasPrefix("✓") ? .green : .red)
            }
            Button("Ada'dan kaldır", role: .destructive) {
                Task {
                    await LiveActivityManager.endAll(reason: "Ada'dan kaldır butonu")
                    self.info = nil
                }
            }
        }
    }

    /// Uçak havadaysa gelen seferin canlı takibi, değilse uçağın (tescil) sayfası.
    /// FR24 uygulaması yüklüyse doğrudan o açılır.
    private func fr24URL(_ info: FlightAttributes.ContentState) -> URL? {
        if let ib = info.inbound, ib.parked == nil, ib.landed == nil, !ib.flight.isEmpty {
            return URL(string: "https://www.flightradar24.com/\(ib.flight.replacingOccurrences(of: " ", with: ""))")
        }
        guard !info.registration.isEmpty else { return nil }
        return URL(string: "https://www.flightradar24.com/data/aircraft/\(info.registration.lowercased())")
    }

    /// TAF'ta işaretlenecek saatler: İstanbul'da kalkış (yeşil) ve dönüş inişi (mavi),
    /// varışta iniş (yeşil) ve dönüş kalkışı (mavi).
    private func weatherEvents(_ info: FlightAttributes.ContentState) -> [String: [WeatherEvent]] {
        var ev: [String: [WeatherEvent]] = [:]
        let dep = info.tsat ?? info.tobt ?? info.eobt
        var ist: [WeatherEvent] = []
        if let dep { ist.append(WeatherEvent(label: "Kalkış", time: dep, isReturn: false)) }
        if let t = info.turn {
            if let ra = t.returnArrival { ist.append(WeatherEvent(label: "Dönüş iniş", time: ra, isReturn: true)) }
            var dst: [WeatherEvent] = []
            if let a = t.outboundArrival { dst.append(WeatherEvent(label: "İniş", time: a, isReturn: false)) }
            if let rd = t.returnDeparture { dst.append(WeatherEvent(label: "Dönüş kalkış", time: rd, isReturn: true)) }
            if !t.destICAO.isEmpty { ev[t.destICAO] = dst }
        }
        ev["LTFM"] = ist
        return ev
    }

    private func plannedRow(_ f: PlannedFlight) -> some View {
        Button {
            Task { await start(planned: f) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.flight).font(.headline.monospaced())
                    Text(dayLabel(f.date)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if loading {
                    ProgressView()
                } else {
                    Label("Ada'ya ekle", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                }
            }
        }
        .disabled(loading)
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = UTC.calendar
        let text = UTCFormat.day(date) + " (UTC)"
        if cal.isDateInToday(date) { return "Bugün · " + text }
        if cal.isDateInTomorrow(date) { return "Yarın · " + text }
        return text
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(Display.text(value)).font(.body.monospaced().bold())
        }
    }

    private func timeRow(_ title: String, _ date: Date?) -> some View {
        LabeledContent(title) {
            if let date {
                Text(date, format: .dateTime.hour().minute()).monospacedDigit()
            } else {
                Text("—")
            }
        }
    }

    // MARK: - İşlemler

    private func loadCurrent() {
        if let a = LiveActivityManager.current {
            info = a.content.state
            if query.isEmpty { query = a.attributes.query }
        } else {
            info = nil
        }
    }

    private func start(planned f: PlannedFlight) async {
        startingPlanned = f
        await start(query: f.flight, plannedDay: f.date)
    }

    private func start(query raw: String, plannedDay: Date?) async {
        if plannedDay == nil { startingPlanned = nil }
        focused = false
        loading = true
        error = nil
        defer { loading = false }
        do {
            let q = CDMFetcher.normalize(raw)
            let state = try await FlightLoader.load(query: raw)

            // Planlı uçuşta CDM başka bir günü gösteriyorsa sor.
            if let plannedDay {
                let departure = state.eobt ?? state.signOn.addingTimeInterval(CDMParser.signOnBeforeEOBT)
                let cal = UTC.calendar
                if !cal.isDate(departure, inSameDayAs: plannedDay), !cal.isDate(state.signOn, inSameDayAs: plannedDay) {
                    let shown = UTCFormat.dayTime(departure) + " UTC"
                    pending = PendingStart(
                        query: q, state: state,
                        message: "CDM şu an \(state.flight) için \(shown) kalkışlı uçuşu gösteriyor. Bu senin \(dayLabel(plannedDay)) uçuşun olmayabilir; CDM o günün uçuşunu genelde aynı gün gösterir.")
                    return
                }
            }
            await begin(query: q, state: state)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func begin(query: String, state: FlightAttributes.ContentState) async {
        if state.hideAt <= Date() {
            error = "Bu uçuşun imza + 30 dk süresi geçmiş, Ada'ya konmadı."
            info = state
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "Ayarlar > Uçuş > Canlı Etkinlikler'i aç."
            return
        }
        do {
            try await LiveActivityManager.start(query: query, state: state)
            if let p = startingPlanned { FlightStore.markStarted(p, hideAt: state.hideAt) }
            loadCurrent()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let oldSignOn = info?.signOn
        if let err = await FlightRefresher.refreshActive() {
            refreshNote = "Yenilenemedi: \(err)"
        } else {
            loadCurrent()
            var note = "✓ Güncellendi \(Date().formatted(.dateTime.hour().minute()))"
            if let oldSignOn, let new = info?.signOn, new != oldSignOn {
                note += " · İmza \(new.formatted(.dateTime.hour().minute())) oldu"
            }
            refreshNote = note
        }
    }
}

// MARK: - Uçuş ekleme

enum UTCFormat {
    private static func style(_ base: Date.FormatStyle) -> Date.FormatStyle {
        var st = base
        st.timeZone = UTC.zone
        st.locale = Locale(identifier: "tr_TR")
        return st
    }
    /// "10 Kasım Pazartesi"
    static func day(_ d: Date) -> String {
        d.formatted(style(.dateTime.day().month(.wide).weekday(.wide)))
    }
    /// "10 Kas"
    static func shortDay(_ d: Date) -> String {
        d.formatted(style(.dateTime.day().month(.abbreviated)))
    }
    /// "10 Kasım 22:30"
    static func dayTime(_ d: Date) -> String {
        d.formatted(style(.dateTime.day().month(.wide).hour().minute()))
    }
}

struct AddFlightView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Date, String) -> Void

    @State private var date = Date()
    @State private var flight = ""
    @State private var added: [String] = []
    @FocusState private var focused: Bool

    private var canAdd: Bool { !flight.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Tarih", selection: $date,
                               in: UTC.calendar.date(byAdding: .day, value: -1, to: UTC.startOfDay(Date()))!...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.timeZone, UTC.zone)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                } header: {
                    Text("Tarih (UTC – roster'daki gibi)")
                }
                Section {
                    TextField("Sefer (1751 ya da TK1751)", text: $flight)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(addCurrent)
                } footer: {
                    Text("Ekledikçe takvim bir sonraki güne geçer; birden fazla uçuşu arka arkaya girebilirsin.")
                }
                if !added.isEmpty {
                    Section("Eklenenler") {
                        ForEach(added, id: \.self) { Text($0) }
                    }
                }
            }
            // Klavye açıkken de hep görünen büyük Ekle butonu
            .safeAreaInset(edge: .bottom) {
                Button(action: addCurrent) {
                    Label("Ekle · \(UTCFormat.shortDay(date))", systemImage: "plus.circle.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAdd)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Uçuş ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private func addCurrent() {
        let f = flight.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return }
        onAdd(date, f)
        added.insert("\(UTCFormat.shortDay(date)) – \(FlightStore.normalizeFlight(f))", at: 0)
        flight = ""
        date = UTC.calendar.date(byAdding: .day, value: 1, to: date) ?? date
        focused = true
    }
}

// MARK: - Ayarlar

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.leaveMinutesKey) private var leaveMinutes = 60

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $leaveMinutes, in: 0...240, step: 5) {
                        LabeledContent("Evden çıkış") {
                            Text(leaveMinutes == 0 ? "Kapalı" : "İmzadan \(Display.minutes(leaveMinutes)) önce")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Çıkış bildirimi")
                } footer: {
                    Text("Bu saate kadar Ada'da yeşil ev sayacı, sonra sarı imza sayacı görünür. O anda chime sesiyle bildirim gelir. Değişiklik bir sonraki Ada'ya eklemede geçerli olur.")
                }
                Section {
                    NavigationLink("Nasıl kullanılır?") { HelpView() }
                    NavigationLink("Tanılama") { DiagnosticsView() }
                }
                if InboundService.isEnabled {
                    Section {
                        let stats = TaxiStats.summary
                        if stats.isEmpty {
                            Text("Henüz ölçüm yok. Gelen uçağı parka girmiş uçuşlara baktıkça birikir.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(stats, id: \.zone) { z in
                            LabeledContent("\(z.zone) standları", value: "\(z.minutes) dk · \(z.count) ölçüm")
                        }
                    } header: {
                        Text("Öğrenilen taksi süreleri")
                    }
                }
                Section {
                    Button("Bildirim sesini dene") {
                        Task { await NotificationManager.test() }
                    }
                } footer: {
                    Text("3 saniye sonra deneme bildirimi gelir. Telefon sessizdeyse ses çalmaz.")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }
}

struct DiagnosticsView: View {
    @State private var lines = DebugLog.lines

    var body: some View {
        List {
            Section {
                if lines.isEmpty { Text("Kayıt yok.").foregroundStyle(.secondary) }
                ForEach(lines, id: \.self) { Text($0).font(.caption.monospaced()) }
            } footer: {
                Text("Ada'dan düşme gibi bir sorun olursa bu ekranın görüntüsünü gönder.")
            }
            Section {
                Button("Kayıtları temizle", role: .destructive) {
                    DebugLog.clear()
                    lines = []
                }
            }
        }
        .navigationTitle("Tanılama")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { lines = DebugLog.lines }
    }
}
