import ActivityKit
import Foundation

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

enum Display {
    static func text(_ s: String) -> String { s.isEmpty ? "—" : s }
}
