import Foundation

/// FlightAware AeroAPI ile uçağın İstanbul'a gelen son seferini bulur.
/// Anahtar derlemede GitHub secret'tan (AEROAPI_KEY) Info.plist'e yazılır; yoksa özellik kapalıdır.
enum InboundService {
    static let airport = "LTFM"

    static var apiKey: String? {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "AeroAPIKey") as? String,
              !k.isEmpty, !k.hasPrefix("$(") else { return nil }
        return k
    }
    static var rapidKey: String? {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "RapidAPIKey") as? String,
              !k.isEmpty, !k.hasPrefix("$(") else { return nil }
        return k
    }
    static var isEnabled: Bool { apiKey != nil || rapidKey != nil }

    /// Önce FlightAware, sonuç yoksa AeroDataBox.
    static func fetch(registration: String, before departure: Date?, stand: String) async -> InboundInfo? {
        let reg = registration.uppercased()
        guard reg.count >= 4 else { return nil }
        if let c = cache[reg], Date().timeIntervalSince(c.date) < 120 { return c.info }
        var info: InboundInfo? = nil
        if apiKey != nil {
            info = await fetchFlightAware(registration: reg, before: departure, stand: stand)
        }
        if info == nil, rapidKey != nil {
            info = await AeroDataBox.fetch(registration: reg, before: departure, stand: stand)
        }
        cache[reg] = (Date(), info)
        return info
    }

    private struct Response: Decodable { let flights: [Flight] }
    private struct Flight: Decodable {
        let ident: String?
        let ident_iata: String?
        let origin: Airport?
        let destination: Airport?
        let scheduled_on: Date?
        let estimated_on: Date?
        let actual_on: Date?
        let scheduled_in: Date?
        let estimated_in: Date?
        let actual_in: Date?
        let cancelled: Bool?

        var arrivalRef: Date? { actual_on ?? estimated_on ?? scheduled_on }
    }
    private struct Airport: Decodable {
        let code_icao: String?
        let code_iata: String?
        let city: String?
    }

    /// Basit önbellek: aynı tescil için 2 dk içinde tekrar sormaz (kota için).
    static var cache: [String: (date: Date, info: InboundInfo?)] = [:]

    private static func fetchFlightAware(registration: String, before departure: Date?, stand: String) async -> InboundInfo? {
        guard let key = apiKey else { return nil }
        let reg = registration.replacingOccurrences(of: "-", with: "")

        var comps = URLComponents(string: "https://aeroapi.flightaware.com/aeroapi/flights/\(reg)")!
        comps.queryItems = [URLQueryItem(name: "ident_type", value: "registration"),
                            URLQueryItem(name: "max_pages", value: "1")]
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "x-apikey")
        req.timeoutInterval = 15

        guard let result = try? await URLSession.shared.data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let data = result.0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let r = try? decoder.decode(Response.self, from: data) else { return nil }

        let limit = departure ?? Date().addingTimeInterval(6 * 3600)
        let inbound = r.flights
            .filter { $0.destination?.code_icao == airport && $0.cancelled != true }
            .filter { ($0.arrivalRef ?? .distantFuture) < limit }
            .max { ($0.arrivalRef ?? .distantPast) < ($1.arrivalRef ?? .distantPast) }

        guard let f = inbound else { return nil }

        // Gerçek taksi süresini öğren
        if let on = f.actual_on, let inn = f.actual_in {
            TaxiStats.record(id: "\(f.ident ?? reg)|\(Int(on.timeIntervalSince1970))",
                             stand: stand, minutes: Int(inn.timeIntervalSince(on) / 60))
        }

        let est = TaxiStats.estimate(stand: stand)
        var info = InboundInfo(
            fromCode: f.origin?.code_iata ?? f.origin?.code_icao ?? "",
            fromCity: f.origin?.city ?? "",
            flight: f.ident_iata ?? f.ident ?? "",
            landed: f.actual_on,
            parked: f.actual_in,
            estimatedLanding: f.actual_on == nil ? (f.estimated_on ?? f.scheduled_on) : nil,
            estimatedPark: nil,
            taxiMinutes: est.minutes,
            taxiSamples: est.samples
        )
        if info.parked == nil, let base = f.actual_on ?? f.estimated_on ?? f.scheduled_on {
            info.estimatedPark = base.addingTimeInterval(Double(est.minutes) * 60)
        }
        return info
    }
}

/// AeroDataBox (RapidAPI) ile tescilden en yakın günün uçuşları.
enum AeroDataBox {
    private struct Flight: Decodable {
        let number: String?
        let status: String?
        let departure: Movement?
        let arrival: Movement?
    }
    private struct Movement: Decodable {
        let airport: Airport?
        let scheduledTime: Time?
        let revisedTime: Time?
        let predictedTime: Time?
        let runwayTime: Time?
        let runway: String?
    }
    private struct Airport: Decodable {
        let icao: String?
        let iata: String?
        let municipalityName: String?
        let shortName: String?
        let name: String?
    }
    private struct Time: Decodable {
        let utc: String?
        var date: Date? { utc.flatMap(AeroDataBox.parse) }
    }

    /// "2026-11-10 16:30Z" / "2026-11-10 16:30:00Z"
    static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mmX", "yyyy-MM-dd HH:mm:ssX", "yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Aynı tescil için 2 dk içinde tekrar istek atmaz (gelen uçak ve dönüş aynı yanıtı kullanır).
    private static var flightsCache: [String: (date: Date, flights: [Flight])] = [:]

    private static func loadFlights(_ registration: String) async -> [Flight]? {
        if let c = flightsCache[registration], Date().timeIntervalSince(c.date) < 120 { return c.flights }
        guard let key = InboundService.rapidKey else { return nil }
        let reg = registration.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? registration
        guard let url = URL(string: "https://aerodatabox.p.rapidapi.com/flights/reg/\(reg)?withAircraftImage=false&withLocation=false") else { return nil }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "x-rapidapi-key")
        req.setValue("aerodatabox.p.rapidapi.com", forHTTPHeaderField: "x-rapidapi-host")
        req.timeoutInterval = 15

        guard let result = try? await URLSession.shared.data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let flights = try? JSONDecoder().decode([Flight].self, from: result.0) else { return nil }
        flightsCache[registration] = (Date(), flights)
        return flights
    }

    /// "TK 94" / "TK0094" -> "TK94"
    static func normFlight(_ s: String) -> String {
        let t = s.uppercased().replacingOccurrences(of: " ", with: "")
        let letters = t.prefix { $0.isLetter }
        let rest = t.dropFirst(letters.count)
        let digits = rest.prefix { $0.isNumber }
        let suffix = rest.dropFirst(digits.count)
        guard let n = Int(digits) else { return t }
        return "\(letters)\(n)\(suffix)"
    }

    /// Bizim seferin varışı ve aynı uçağın İstanbul'a dönüş seferi.
    static func turn(registration: String, flight: String) async -> TurnInfo? {
        guard let flights = await loadFlights(registration.uppercased()) else { return nil }
        let ours = normFlight(flight)
        guard let out = flights.first(where: {
            normFlight($0.number ?? "") == ours && $0.departure?.airport?.icao == InboundService.airport
        }), let dest = out.arrival?.airport else { return nil }

        func depRef(_ f: Flight) -> Date? {
            f.departure?.runwayTime?.date ?? f.departure?.revisedTime?.date ?? f.departure?.scheduledTime?.date
        }
        let outArrival = out.arrival?.runwayTime?.date ?? out.arrival?.revisedTime?.date
            ?? out.arrival?.predictedTime?.date ?? out.arrival?.scheduledTime?.date
        let after = outArrival ?? depRef(out) ?? .distantPast
        let back = flights
            .filter { $0.departure?.airport?.icao == dest.icao && $0.arrival?.airport?.icao == InboundService.airport }
            .filter { (depRef($0) ?? .distantPast) > after }
            .min { (depRef($0) ?? .distantFuture) < (depRef($1) ?? .distantFuture) }

        return TurnInfo(
            destICAO: dest.icao ?? "",
            destIATA: dest.iata ?? "",
            destCity: dest.municipalityName ?? dest.shortName ?? "",
            outboundArrival: outArrival,
            returnFlight: back.map { ($0.number ?? "").replacingOccurrences(of: " ", with: "") },
            returnDeparture: back.flatMap(depRef),
            returnArrival: back.flatMap { $0.arrival?.revisedTime?.date ?? $0.arrival?.predictedTime?.date ?? $0.arrival?.scheduledTime?.date }
        )
    }

    static func fetch(registration: String, before departure: Date?, stand: String) async -> InboundInfo? {
        guard let flights = await loadFlights(registration) else { return nil }

        let limit = departure ?? Date().addingTimeInterval(6 * 3600)
        func arrivalRef(_ f: Flight) -> Date? {
            f.arrival?.runwayTime?.date ?? f.arrival?.revisedTime?.date ?? f.arrival?.scheduledTime?.date
        }
        let inbound = flights
            .filter { $0.arrival?.airport?.icao == InboundService.airport && ($0.status ?? "") != "Canceled" }
            .filter { (arrivalRef($0) ?? .distantFuture) < limit }
            .max { (arrivalRef($0) ?? .distantPast) < (arrivalRef($1) ?? .distantPast) }
        guard let f = inbound, let arr = f.arrival else { return nil }

        let landed = arr.runwayTime?.date
        let arrived = (f.status ?? "").lowercased().hasPrefix("arrived")
        // revisedTime varış için kapıya geliş saatidir; iniş saatinden sonraysa park saati say.
        var parked: Date? = nil
        if arrived, let rev = arr.revisedTime?.date {
            if let landed { parked = rev > landed ? rev : nil } else { parked = rev }
        }
        if let landed, let parked {
            TaxiStats.record(id: "\(f.number ?? registration)|\(Int(landed.timeIntervalSince1970))",
                             stand: stand, minutes: Int(parked.timeIntervalSince(landed) / 60))
        }

        let est = TaxiStats.estimate(stand: stand)
        let origin = f.departure?.airport
        var info = InboundInfo(
            fromCode: origin?.iata ?? origin?.icao ?? "",
            fromCity: origin?.municipalityName ?? origin?.shortName ?? "",
            flight: (f.number ?? "").replacingOccurrences(of: " ", with: ""),
            landed: landed,
            parked: parked,
            estimatedLanding: landed == nil ? (arr.predictedTime?.date ?? arr.revisedTime?.date ?? arr.scheduledTime?.date) : nil,
            estimatedPark: nil,
            taxiMinutes: est.minutes,
            taxiSamples: est.samples
        )
        info.landingRunway = arr.runway
        if parked == nil, !(arrived && landed == nil),
           let base = landed ?? info.estimatedLanding {
            info.estimatedPark = base.addingTimeInterval(Double(est.minutes) * 60)
        }
        return info
    }
}

/// İnişten parka gerçek taksi sürelerini stand bölgesine göre (A, B, F...) biriktirir.
enum TaxiStats {
    private static let samplesKey = "taxiSamples"
    private static let seenKey = "taxiSeen"
    static let defaultMinutes = 12

    /// "F13L" -> "F", "A3L" -> "A"
    static func zone(_ stand: String) -> String {
        let z = stand.uppercased().prefix { $0.isLetter }
        return z.isEmpty ? "?" : String(z)
    }

    private static var samples: [String: [Int]] {
        get { (UserDefaults.standard.dictionary(forKey: samplesKey) as? [String: [Int]]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: samplesKey) }
    }

    static func record(id: String, stand: String, minutes: Int) {
        guard (2...60).contains(minutes), !stand.isEmpty else { return }
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        guard !seen.contains(id) else { return }
        seen.insert(id)
        UserDefaults.standard.set(Array(seen.suffix(300)), forKey: seenKey)

        var all = samples
        all[zone(stand), default: []].append(minutes)
        all[zone(stand)] = Array(all[zone(stand)]!.suffix(40))
        samples = all
    }

    /// Bölgenin ortanca taksi süresi; veri yoksa tüm bölgelerin ortancası, o da yoksa 12 dk.
    static func estimate(stand: String) -> (minutes: Int, samples: Int) {
        let all = samples
        if let list = all[zone(stand)], list.count >= 2 { return (median(list), list.count) }
        let every = all.values.flatMap { $0 }
        if every.count >= 3 { return (median(every), 0) }
        return (defaultMinutes, 0)
    }

    struct ZoneStat: Hashable {
        let zone: String
        let minutes: Int
        let count: Int
    }

    static var summary: [ZoneStat] {
        samples.map { ZoneStat(zone: $0.key, minutes: median($0.value), count: $0.value.count) }
            .sorted { $0.zone < $1.zone }
    }

    private static func median(_ v: [Int]) -> Int {
        let s = v.sorted()
        return s.isEmpty ? defaultMinutes : s[s.count / 2]
    }
}

/// CDM + FlightAware'i birlikte çeker.
@MainActor
enum FlightLoader {
    static func load(query: String) async throws -> FlightAttributes.ContentState {
        var state = try await CDMFetcher.shared.fetch(query: query)
        state.inbound = await InboundService.fetch(registration: state.registration,
                                                   before: state.eobt, stand: state.stand)
        if InboundService.rapidKey != nil, !state.registration.isEmpty {
            state.turn = await AeroDataBox.turn(registration: state.registration, flight: state.flight)
        }
        return state
    }
}
