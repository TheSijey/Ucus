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
        var leaveAt: Date? = nil    // evden çıkış (imza - ayar); yoksa sadece imza sayacı
        var inbound: InboundInfo? = nil  // uçağın gelen seferi
        var turn: TurnInfo? = nil        // varış ve dönüş seferi
    }

    /// Kullanıcının aradığı şey (1751, LTD ...). Yenilemede tekrar kullanılır.
    var query: String
}

/// Bizim seferin varışı ve aynı uçağın İstanbul'a dönüşü.
struct TurnInfo: Codable, Hashable {
    var destICAO: String
    var destIATA: String
    var destCity: String
    var outboundArrival: Date?
    var returnFlight: String?
    var returnDeparture: Date?
    var returnArrival: Date?
    var destGateToday: String? = nil      // dönüşün kalkış gate'i (bugün, yayınlandıysa)
    var destGateHistory: [String] = []    // son günlerdeki gate'ler
    var arrivalGateToday: String? = nil   // varış gate'i (bazı meydanlar yayınlar)
}

/// Uçağın İstanbul'a gelen son seferi.
struct InboundInfo: Codable, Hashable {
    var fromCode: String         // "AYT"
    var fromCity: String         // "Antalya"
    var flight: String           // "TK2411"
    var landed: Date?            // gerçek iniş
    var parked: Date?            // gerçek parka giriş
    var estimatedLanding: Date?  // henüz inmediyse
    var estimatedPark: Date?     // henüz parkta değilse: iniş + taksi
    var taxiMinutes: Int?        // kullanılan taksi tahmini
    var taxiSamples: Int?        // tahminin dayandığı ölçüm sayısı
    var landingRunway: String? = nil  // iniş pisti (varsa)
}

extension FlightAttributes.ContentState {
    /// İmza saatinden 30 dk sonra kaybolur.
    var hideAt: Date { signOn.addingTimeInterval(30 * 60) }

    /// "TC-LTD" -> "LTD"
    var shortRegistration: String {
        registration.components(separatedBy: "-").last ?? registration
    }

    /// Evden çıkış saati henüz gelmediyse onu döndürür.
    func upcomingLeave(now: Date = Date()) -> Date? {
        guard let leaveAt, now < leaveAt else { return nil }
        return leaveAt
    }
}

/// Hedefe kalan süre; kendi kendine her saniye işler (güncelleme gerekmez). Hedefe gelince 0:00'da durur.
struct Countdown: View {
    let target: Date
    var body: some View {
        Text(timerInterval: target.addingTimeInterval(-86_400)...target, countsDown: true)
            .monospacedDigit()
    }
}

/// Çıkış saatine kadar yeşil ev sayacı, sonra sarı imza sayacı.
struct PhaseCountdown: View {
    let state: FlightAttributes.ContentState
    var showLabel = true
    var showIcon = false

    var body: some View {
        if let leave = state.upcomingLeave() {
            HStack(spacing: 3) {
                if showIcon { Image(systemName: "house.fill").font(.system(size: 8)) }
                if showLabel { Text("Çıkışa").foregroundStyle(.secondary) }
                Countdown(target: leave)
            }
            .foregroundStyle(.green)
        } else {
            HStack(spacing: 3) {
                if showLabel { Text("İmzaya").foregroundStyle(.secondary) }
                Countdown(target: state.signOn)
            }
            .foregroundStyle(.yellow)
        }
    }
}

enum Display {
    static func text(_ s: String) -> String { s.isEmpty ? "—" : s }

    /// 60 -> "1 saat", 75 -> "1 saat 15 dk", 45 -> "45 dk"
    static func minutes(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        switch (h, r) {
        case (0, _): return "\(r) dk"
        case (_, 0): return "\(h) saat"
        default: return "\(h) saat \(r) dk"
        }
    }
}

/// "47 dk önce" / "2 sa 5 dk önce" – saniyesiz, dakikada bir güncellenir.
struct MinutesAgo: View {
    let date: Date
    var suffix = " önce"

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(Self.text(from: date, to: ctx.date) + suffix)
        }
    }

    static func text(from: Date, to: Date) -> String {
        let m = max(0, Int(to.timeIntervalSince(from) / 60))
        if m < 60 { return "\(m) dk" }
        return m % 60 == 0 ? "\(m / 60) sa" : "\(m / 60) sa \(m % 60) dk"
    }
}
