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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFlightView { date, flight in store.add(date: date, flight: flight) }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
            }
            .refreshable { await refresh() }
        }
    }

    // MARK: - Bölümler

    @ViewBuilder
    private func activeSection(_ info: FlightAttributes.ContentState) -> some View {
        Section("Ada'da") {
            row("Sefer", "\(info.flight)  →  \(Display.text(info.destination))")
            row("Tescil", "\(Display.text(info.registration))  ·  \(Display.text(info.aircraftType))")
            row("Stand", info.stand)
            row("Gate", info.gate)
            row("Pist", info.runway)
        }
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
            Button("Yenile") { Task { await refresh() } }
            Button("Ada'dan kaldır", role: .destructive) {
                Task {
                    await LiveActivityManager.endAll()
                    self.info = nil
                }
            }
        }
    }

    private func plannedRow(_ f: PlannedFlight) -> some View {
        Button {
            Task { await start(query: f.flight, plannedDay: f.date) }
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
        let cal = Calendar.current
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR")))
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

    private func start(query raw: String, plannedDay: Date?) async {
        focused = false
        loading = true
        error = nil
        defer { loading = false }
        do {
            let q = CDMFetcher.normalize(raw)
            let state = try await CDMFetcher.shared.fetch(query: raw)

            // Planlı uçuşta CDM başka bir günü gösteriyorsa sor.
            if let plannedDay {
                let departure = state.eobt ?? state.signOn.addingTimeInterval(CDMParser.signOnBeforeEOBT)
                if !Calendar.current.isDate(departure, inSameDayAs: plannedDay) {
                    let shown = departure.formatted(.dateTime.day().month(.wide).hour().minute()
                        .locale(Locale(identifier: "tr_TR")))
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
            loadCurrent()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        await FlightRefresher.refreshActive()
        loadCurrent()
    }
}

// MARK: - Uçuş ekleme

struct AddFlightView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Date, String) -> Void

    @State private var date = Date()
    @State private var flight = ""
    @State private var added: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Tarih", selection: $date,
                               in: Calendar.current.startOfDay(for: Date())...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                    TextField("Sefer (1751 ya da TK1751)", text: $flight)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(addCurrent)
                    Button("Ekle", action: addCurrent)
                        .disabled(flight.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("Ekledikçe takvim bir sonraki güne geçer; birden fazla uçuşu arka arkaya girebilirsin.")
                }
                if !added.isEmpty {
                    Section("Eklenenler") {
                        ForEach(added, id: \.self) { Text($0) }
                    }
                }
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
        let label = date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR")))
        added.insert("\(label) – \(FlightStore.normalizeFlight(f))", at: 0)
        flight = ""
        date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
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
