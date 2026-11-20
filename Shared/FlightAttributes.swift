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
        var sid: String? = nil           // kalkış SID (CDM)
        // Dış meydan kalkışı (CDM yok, AeroDataBox): kalkış meydanı ve elle girilen saatler
        var origin: String? = nil        // "OLBA"; nil = İstanbul (CDM)
        var originIATA: String? = nil    // "BEY"
        var originCity: String? = nil    // "Beirut"
        var originTZ: String? = nil      // "Asia/Beirut"
        var signOnManual: Bool? = nil    // imza elle girildi (yoksa tahmin)
        var pickupAt: Date? = nil        // otelden çıkış (elle)
        // Kullanıcının belirlediği bacaklar (ilk sefer hariç). nil: dönüş otomatik tahmin; []: tek bacak.
        var tripLegs: [String]? = nil
        var extraLegs: [LegInfo]? = nil  // dönüşten sonraki bacaklar (3., 4. ...)
        var isPreview: Bool? = nil       // CDM'de henüz yok: tarifeden ön izleme
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
    var destRunwayHistory: [String] = []  // son günlerde varışta kullanılan iniş pistleri
    var returnToICAO: String? = nil       // ikinci bacağın varışı (nil = İstanbul)
    var returnToIATA: String? = nil
}

/// Dönüşten sonraki bir bacak.
struct LegInfo: Codable, Hashable {
    var flight: String
    var fromICAO: String
    var fromIATA: String
    var toICAO: String
    var toIATA: String
    var toCity: String
    var departure: Date?
    var arrival: Date?
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
    var isAssumed: Bool? = nil        // gerçek saat yok; tahmini saat geçtiği için inmiş/parkta sayıldı
}

extension InboundInfo {
    /// "~" işareti (saatler tahminiyse)
    var approx: String { isAssumed == true ? "~" : "" }
}

/// "00:33" ya da başka gündeyse "dün 00:33"
enum DayClock {
    static func text(_ d: Date) -> String {
        let cal = Calendar.current
        let t = d.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(d) { return t }
        if cal.isDateInYesterday(d) { return L("dün \(t)", "yesterday \(t)") }
        return d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Lang.locale))
    }
}

extension FlightAttributes.ContentState {
    /// İmza saatinden 30 dk sonra kaybolur.
    var hideAt: Date { signOn.addingTimeInterval(30 * 60) }

    /// Turun bittiği an: dönüş inişi; dönüş yoksa (tek yön) varış + 30 dk; o da yoksa imza + 6 sa.
    var tourEnd: Date {
        if let last = extraLegs?.last, let a = last.arrival ?? last.departure.map({ $0.addingTimeInterval(3 * 3600) }) {
            return max(a.addingTimeInterval(last.toICAO == "LTFM" ? 0 : 30 * 60), hideAt)
        }
        let end = turn?.returnArrival
            ?? turn?.outboundArrival.map { $0.addingTimeInterval(30 * 60) }
            ?? signOn.addingTimeInterval(6 * 3600)
        return max(end, hideAt)
    }

    /// Dış meydandan kalkış (CDM yok).
    var isOutstation: Bool { origin != nil }
    /// Dönüşü olmayan uçuş (yatılı ya da dış meydandan gelen).
    var isOneWay: Bool {
        if let last = extraLegs?.last { return last.toICAO != "LTFM" }
        return turn != nil && turn?.returnFlight == nil
    }
    /// Son inişin saati (tüm bacaklar).
    var lastArrival: Date? { extraLegs?.last?.arrival ?? turn?.returnArrival ?? turn?.outboundArrival }
    /// Kalkış meydanı kodu: "IST" ya da "BEY".
    var originCode: String { originIATA ?? (origin ?? "IST") }
    /// Kalkış meydanının saat dilimi.
    var originTimeZone: TimeZone { originTZ.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Istanbul")! }
    /// Gidiş seferinin kalkış saati.
    var departureTime: Date? { tsat ?? tobt ?? eobt }

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
                if showIcon { Image(systemName: state.isOutstation ? "building.2.fill" : "house.fill").font(.system(size: 8)) }
                if showLabel { Text(L("Çıkışa", "Leave")).foregroundStyle(.secondary) }
                Countdown(target: leave)
            }
            .foregroundStyle(.green)
        } else {
            HStack(spacing: 3) {
                if showLabel { Text(L("İmzaya", "Sign-on")).foregroundStyle(.secondary) }
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
        case (0, _): return L("\(r) dk", "\(r) min")
        case (_, 0): return L("\(h) saat", "\(h) h")
        default: return L("\(h) saat \(r) dk", "\(h) h \(r) min")
        }
    }
}

/// "47 dk önce" / "2 sa 5 dk önce" – saniyesiz, dakikada bir güncellenir.
struct MinutesAgo: View {
    let date: Date
    var suffix = L(" önce", " ago")

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(Self.text(from: date, to: ctx.date) + suffix)
        }
    }

    static func text(from: Date, to: Date) -> String {
        let m = max(0, Int(to.timeIntervalSince(from) / 60))
        if m < 60 { return L("\(m) dk", "\(m) min") }
        return m % 60 == 0 ? L("\(m / 60) sa", "\(m / 60) h") : L("\(m / 60) sa \(m % 60) dk", "\(m / 60) h \(m % 60) min")
    }
}


extension FlightAttributes.ContentState {
    /// Gelen uçak bilgisi; 12 saatten eski kayıtlar (önceki günlerin seferi) gösterilmez.
    var freshInbound: InboundInfo? {
        guard let ib = inbound else { return nil }
        let latest = [ib.parked, ib.estimatedPark, ib.landed, ib.estimatedLanding].compactMap { $0 }.max()
        guard let latest else { return ib }
        return Date().timeIntervalSince(latest) < 12 * 3600 ? ib : nil
    }
}
