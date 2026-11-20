import SwiftUI

/// Uygulamanın kökü: 5 sekme (Bugün · Brifing · Hava · Meydanlar · Uçuşlarım). Tur, Bugün içinde "Günün akışı".
struct ContentView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var session = FlightSession.shared
    @AppStorage("onboardingDone2") private var onboardingDone = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Lang.key, store: SharedStore.defaults) private var language = "system"

    var body: some View {
        TabView(selection: $model.tab) {
            TodayView()
                .tabItem { Label(L("Bugün", "Today"), systemImage: "rectangle.topthird.inset.filled") }
                .tag(AppTab.today)
            BriefingView()
                .tabItem { Label(L("Brifing", "Briefing"), systemImage: "list.clipboard") }
                .tag(AppTab.briefing)
            WeatherView()
                .tabItem { Label(L("Hava", "Weather"), systemImage: "cloud.sun") }
                .tag(AppTab.weather)
            AirportsView()
                .tabItem { Label(L("Meydanlar", "Airports"), systemImage: "mappin.and.ellipse") }
                .tag(AppTab.airports)
            FlightsView(store: model.store)
                .tabItem { Label(L("Uçuşlarım", "My Flights"), systemImage: "list.bullet") }
                .tag(AppTab.flights)
        }
        .tabViewStyle(.sidebarAdaptable)   // iPad'de kenar çubuğu
        .id(language)   // dil değişince tüm ekranlar yeniden çizilir
        .environmentObject(model)
        .tint(Palette.stand)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showAdd) {
            AddFlightView { p in model.store.add(date: p.date, flight: p.flight, kind: p.kind, legs: p.legs, airports: p.airports) }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        .sheet(item: $model.recordRequest) { RecordSheet(request: $0).environmentObject(model) }
        .onReceive(NotificationCenter.default.publisher(for: .openFlightRecord)) { _ in
            if let s = session.recent { model.recordRequest = RecordRequest.forCurrent(s) }
        }
        .alert(L("Tarih farklı", "Different date"), isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            Button(L("Yine de ekle", "Add anyway")) {
                if let p = model.pending { Task { await model.begin(query: p.query, state: p.state) } }
                model.pending = nil
            }
            Button(L("Vazgeç", "Cancel"), role: .cancel) { model.pending = nil }
        } message: {
            Text(model.pending?.message ?? "")
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingView()
        }
        .onOpenURL { url in
            if url.isFileURL {
                // Dosyalar / paylaş menüsünden açılan briefing PDF'i: takip edilen uçuşun NOTAM'larına aktarılır
                let text = NotamParser.pdfText(url)
                NotamStore.removeCopy(url)   // iOS'un uygulamaya koyduğu kopya okununca silinir
                if let s = session.state, let text, !text.isEmpty {
                    NotamStore.shared.importText(text, source: url.lastPathComponent, key: BriefingStore.key(for: s), airports: FlightHelpers.airports(s))
                    model.tab = .briefing
                } else if session.state == nil {
                    model.error = L("NOTAM'ları aktarmak için önce uçuşu başlat.", "Start the flight first to import NOTAMs.")
                }
                return
            }
            guard url.scheme == "ucus" else { return }
            if url.host == "refresh" {
                model.tab = .today
                Task { await model.refresh() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.store.prune()
                ActivityObserver.watchAll()
                LiveActivityManager.ensureActivity()
                if let s = session.state, Date().timeIntervalSince(s.updatedAt) > 180 {
                    Task { await model.refresh() }
                }
            }
        }
        .task {
            NotamStore.purgeInbox()
            model.store.prune()
            ActivityObserver.watchAll()
            if session.state == nil { model.tab = .flights }
        }
    }
}

/// Sekmelerin ortak araç çubuğu: Ayarlar, Yenile.
struct CommonToolbar: ToolbarContent {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { model.showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel(L("Ayarlar", "Settings"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            if session.state != nil {
                Button { Task { await model.refresh() } } label: {
                    if model.loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(model.loading)
                .accessibilityLabel(L("Yenile", "Refresh"))
            }
        }
    }
}
