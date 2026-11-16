import AppIntents
import Foundation

/// "Hey Siri, Uçuş'ta uçuşumu başlat": listedeki ilk (bugünkü) uçuşu Ada'ya ekler.
struct StartNextFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "Uçuşumu başlat"
    static var description = IntentDescription("Uçuşlarım listesindeki sıradaki uçuşu CDM'den çekip takibini başlatır.")
    /// CDM sayfası görünmez tarayıcıda açıldığı için uygulama kısa süre açılır.
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FlightStore()
        guard let planned = store.upcoming.first else {
            return .result(dialog: IntentDialog(stringLiteral: L("Uçuşlarım listende uçuş yok. Önce uygulamadan ekle.", "Your My Flights list is empty. Add one in the app first.")))
        }
        let state: FlightAttributes.ContentState
        do {
            state = try await FlightLoader.load(query: planned.flight, legs: planned.legNumbers)
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: L("\(planned.flight) CDM'den okunamadı. Uygulamadan tekrar dene.", "Couldn't read \(planned.flight) from CDM. Try again in the app.")))
        }

        let departure = state.eobt ?? state.signOn.addingTimeInterval(CDMParser.signOnBeforeEOBT)
        let cal = UTC.calendar
        guard cal.isDate(departure, inSameDayAs: planned.date) || cal.isDate(state.signOn, inSameDayAs: planned.date) else {
            return .result(dialog: IntentDialog(stringLiteral: L("CDM şu an \(planned.flight) için başka bir günün uçuşunu gösteriyor. Uçuş günü tekrar dene.", "CDM currently shows another day's \(planned.flight). Try again on the flight day.")))
        }
        guard state.hideAt > Date() else {
            return .result(dialog: IntentDialog(stringLiteral: L("\(planned.flight) uçuşunun süresi geçmiş.", "\(planned.flight) is already over.")))
        }

        do {
            try await LiveActivityManager.start(query: CDMFetcher.normalize(planned.flight), state: state)
            FlightStore.markStarted(planned, until: FlightSession.shared.state?.tourEnd ?? state.tourEnd)
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: L("Takip başlatılamadı. Ayarlar'da Canlı Etkinlikler açık mı?", "Couldn't start tracking. Are Live Activities on in Settings?")))
        }

        let signOn = state.signOn.formatted(.dateTime.hour().minute())
        let stand = state.stand.isEmpty ? L("henüz yok", "not yet") : state.stand
        return .result(dialog: IntentDialog(stringLiteral: L("\(state.flight) takip ediliyor. Stand \(stand), imza \(signOn).", "Tracking \(state.flight). Stand \(stand), sign-on \(signOn).")))
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
                "\(.applicationName) takibi başlat",
                "Start my flight in \(.applicationName)",
            ],
            shortTitle: "Uçuşumu başlat",
            systemImageName: "airplane.departure"
        )
    }
}
