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
    static var isEnabled: Bool { apiKey != nil }

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
    private static var cache: [String: (date: Date, info: InboundInfo?)] = [:]

    static func fetch(registration: String, before departure: Date?, stand: String) async -> InboundInfo? {
        guard let key = apiKey else { return nil }
        let reg = registration.replacingOccurrences(of: "-", with: "").uppercased()
        guard reg.count >= 4 else { return nil }

        if let c = cache[reg], Date().timeIntervalSince(c.date) < 120 { return c.info }

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

        guard let f = inbound else {
            cache[reg] = (Date(), nil)
            return nil
        }

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
        cache[reg] = (Date(), info)
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
        return state
    }
}
