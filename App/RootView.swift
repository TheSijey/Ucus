import SwiftUI

/// Uygulamanın kökü: 4 sekme (Bugün · Tur · Hava · Uçuşlarım).
struct ContentView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var session = FlightSession.shared
    @AppStorage("onboardingDone2") private var onboardingDone = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $model.tab) {
            TodayView()
                .tabItem { Label("Bugün", systemImage: "rectangle.topthird.inset.filled") }
                .tag(AppTab.today)
            TourView()
                .tabItem { Label("Tur", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(AppTab.tour)
            WeatherTab()
                .tabItem { Label("Hava", systemImage: "cloud.sun") }
                .tag(AppTab.weather)
            FlightsView(store: model.store)
                .tabItem { Label("Uçuşlarım", systemImage: "list.bullet") }
                .tag(AppTab.flights)
        }
        .environmentObject(model)
        .tint(Palette.stand)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showAdd) {
            AddFlightView { date, flight in model.store.add(date: date, flight: flight) }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        .alert("Tarih farklı", isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            Button("Yine de ekle") {
                if let p = model.pending { Task { await model.begin(query: p.query, state: p.state) } }
                model.pending = nil
            }
            Button("Vazgeç", role: .cancel) { model.pending = nil }
        } message: {
            Text(model.pending?.message ?? "")
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingView()
        }
        .onOpenURL { url in
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
                if let s = session.state, Date().timeIntervalSince(s.updatedAt) > 180 {
                    Task { await model.refresh() }
                }
            }
        }
        .task {
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
                .accessibilityLabel("Ayarlar")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if session.state != nil {
                Button { Task { await model.refresh() } } label: {
                    if model.loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(model.loading)
                .accessibilityLabel("Yenile")
            }
        }
    }
}
