import ActivityKit
import Foundation
import SwiftUI

/// Canlı Etkinlik verisi. Hem uygulama hem widget eklentisi kullanır.
struct FlightAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var flight: String          // "TK1751"
        var callsign: String        // "THY5VZ"
        var registration: String    // "TC-LTD"
        var aircraftType: String    // "32Q"
        var destination: String     // "OSL"
        var gate: String            // "A3A"
        var stand: String           // "A3L"
        var runway: String          // "35R"
        var eobt: Date?
        var tobt: Date?
        var tsat: Date?
        var ctot: Date?
        var signOn: Date            // EOBT - 1:15
        var updatedAt: Date
    }

    /// Kullanıcının aradığı şey (1751, LTD ...). Yenilemede tekrar kullanılır.
    var query: String
}

extension FlightAttributes.ContentState {
    /// İmza saatinden 30 dk sonra kaybolur.
    var hideAt: Date { signOn.addingTimeInterval(30 * 60) }

    /// "TC-LTD" -> "LTD"
    var shortRegistration: String {
        registration.components(separatedBy: "-").last ?? registration
    }
}

/// İmzaya kalan süre; kendi kendine her saniye işler (güncelleme gerekmez). İmza gelince 0:00'da durur.
struct SignOnCountdown: View {
    let signOn: Date
    var body: some View {
        Text(timerInterval: signOn.addingTimeInterval(-86_400)...signOn, countsDown: true)
            .monospacedDigit()
    }
}

enum Display {
    static func text(_ s: String) -> String { s.isEmpty ? "—" : s }
}
