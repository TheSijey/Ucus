import AppIntents
import Foundation

/// Kilit ekranı / Ada'daki "Yenile" butonu. LiveActivityIntent olduğu için
/// uygulamanın kendi içinde (arka planda) çalışır.
struct RefreshFlightIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Uçuşu yenile"
    static var description = IntentDescription("Stand ve saatleri CDM'den tekrar çeker. / Refreshes stand and times from CDM.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await FlightRefresher.refreshActive()
        #endif
        return .result()
    }
}
