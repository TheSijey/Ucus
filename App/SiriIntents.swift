import AppIntents
import Foundation

/// "Hey Siri, Uçuş'ta uçuşumu başlat": listedeki ilk (bugünkü) uçuşu Ada'ya ekler.
struct StartNextFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "Uçuşumu başlat"
    static var description = IntentDescription("Uçuşlarım listesindeki sıradaki uçuşu CDM'den çekip Ada'ya ekler.")
    /// CDM sayfası görünmez tarayıcıda açıldığı için uygulama kısa süre açılır.
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FlightStore()
        guard let planned = store.upcoming.first else {
            return .result(dialog: "Uçuşlarım listende uçuş yok. Önce uygulamadan ekle.")
        }
        let state: FlightAttributes.ContentState
        do {
            state = try await FlightLoader.load(query: planned.flight)
        } catch {
            return .result(dialog: "\(planned.flight) CDM'den okunamadı. Uygulamadan tekrar dene.")
        }

        let departure = state.eobt ?? state.signOn.addingTimeInterval(CDMParser.signOnBeforeEOBT)
        let cal = UTC.calendar
        guard cal.isDate(departure, inSameDayAs: planned.date) || cal.isDate(state.signOn, inSameDayAs: planned.date) else {
            return .result(dialog: "CDM şu an \(planned.flight) için başka bir günün uçuşunu gösteriyor. Uçuş günü tekrar dene.")
        }
        guard state.hideAt > Date() else {
            return .result(dialog: "\(planned.flight) uçuşunun süresi geçmiş.")
        }

        do {
            try await LiveActivityManager.start(query: CDMFetcher.normalize(planned.flight), state: state)
            FlightStore.markStarted(planned, hideAt: state.hideAt)
        } catch {
            return .result(dialog: "Ada'ya eklenemedi. Ayarlar'da Canlı Etkinlikler açık mı?")
        }

        let signOn = state.signOn.formatted(.dateTime.hour().minute())
        let stand = state.stand.isEmpty ? "henüz yok" : state.stand
        return .result(dialog: "\(state.flight) Ada'ya eklendi. Stand \(stand), imza \(signOn).")
    }
}

/// Kısayollar ve Siri'de kendiliğinden görünen komutlar.
struct UcusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNextFlightIntent(),
            phrases: [
                "\(.applicationName)'ta uçuşumu başlat",
                "\(.applicationName) uçuşumu başlat",
                "\(.applicationName) Ada'ya ekle",
                "Start my flight in \(.applicationName)",
            ],
            shortTitle: "Uçuşumu başlat",
            systemImageName: "airplane.departure"
        )
    }
}
