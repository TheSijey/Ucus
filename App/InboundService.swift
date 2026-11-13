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

    /// Aynı tescil ve günler için 10 dk içinde tekrar istek atmaz (geliş, gidiş ve dönüş aynı listeyi kullanır).
    private static var flightsCache: [String: (date: Date, flights: [Flight])] = [:]

    /// Uçağın kalkış gününe (İstanbul saati) ait tüm uçuşları; sabah erken kalkışta önceki gün,
    /// öğleden sonra kalkışta ertesi gün de eklenir (gelen uçak / gece dönüşü için).
    private static func loadFlights(_ registration: String, around: Date?) async -> [Flight]? {
        guard InboundService.rapidKey != nil else { return nil }
        let ref = around ?? Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let hour = cal.component(.hour, from: ref)
        var days = [ref]
        if hour < 9, let d = cal.date(byAdding: .day, value: -1, to: ref) { days.insert(d, at: 0) }
        if hour >= 12, let d = cal.date(byAdding: .day, value: 1, to: ref) { days.append(d) }
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let dayStrings = days.map { fmt.string(from: $0) }

        let cacheKey = registration + "|" + dayStrings.joined(separator: ",")
        if let c = flightsCache[cacheKey], Date().timeIntervalSince(c.date) < 600 { return c.flights }

        var all: [Flight] = []
        var anyOK = false
        for day in dayStrings {
            if let list = await request(path: "flights/reg/\(registration)/\(day)") {
                anyOK = true
                all += list
            }
        }
        if !anyOK || all.isEmpty {
            // Yedek: uçağın o anki uçuşu
            if let list = await request(path: "flights/reg/\(registration)") { anyOK = true; all += list }
        }
        guard anyOK else { return nil }

        // Aynı uçuş iki günde de gelebilir: sefer + planlanan kalkışa göre tekilleştir
        var seen = Set<String>()
        all = all.filter { f in
            let k = "\(f.number ?? "")|\(f.departure?.scheduledTime?.utc ?? "")"
            return seen.insert(k).inserted
        }
        flightsCache[cacheKey] = (Date(), all)
        return all
    }

    private static func request(path: String) async -> [Flight]? {
        guard let key = InboundService.rapidKey,
              let url = URL(string: "https://aerodatabox.p.rapidapi.com/\(path)?withAircraftImage=false&withLocation=false")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "x-rapidapi-key")
        req.setValue("aerodatabox.p.rapidapi.com", forHTTPHeaderField: "x-rapidapi-host")
        req.timeoutInterval = 15
        guard let result = try? await URLSession.shared.data(for: req),
              let http = result.1 as? HTTPURLResponse else {
            DebugLog.add("AeroDataBox \(path): bağlantı hatası")
            return nil
        }
        if http.statusCode == 204 { return [] }
        guard http.statusCode == 200,
              let flights = try? JSONDecoder().decode([Flight].self, from: result.0) else {
            let body = String(data: result.0.prefix(120), encoding: .utf8) ?? ""
            DebugLog.add("AeroDataBox \(path): HTTP \(http.statusCode) \(body)")
            return nil
        }
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

    /// Sefer numarasıyla o günün uçuşu (uçak ataması gerekmez; planlı uçuşlar da gelir).
    private static var numberCache: [String: (date: Date, flights: [Flight])] = [:]

    private static func byNumber(_ flight: String, day: String) async -> [Flight] {
        let key = flight + "|" + day
        if let c = numberCache[key], Date().timeIntervalSince(c.date) < 3600 { return c.flights }
        let list = await request(path: "flights/number/\(flight)/\(day)") ?? []
        numberCache[key] = (Date(), list)
        return list
    }

    private static func istanbulDays(_ ref: Date, plus extra: Int = 0) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return (0...extra).compactMap { cal.date(byAdding: .day, value: $0, to: ref) }.map { fmt.string(from: $0) }
    }

    /// Bizim seferin varışı ve dönüş seferi (TK1751 → TK1752, olmazsa TK1750).
    static func turn(registration: String, flight: String, around: Date?) async -> TurnInfo? {
        let ref = around ?? Date()
        let ours = normFlight(flight)
        guard let day = istanbulDays(ref).first else { return nil }

        func depRef(_ f: Flight) -> Date? {
            f.departure?.runwayTime?.date ?? f.departure?.revisedTime?.date ?? f.departure?.scheduledTime?.date
        }
        func arrRef(_ f: Flight) -> Date? {
            f.arrival?.runwayTime?.date ?? f.arrival?.revisedTime?.date ?? f.arrival?.predictedTime?.date ?? f.arrival?.scheduledTime?.date
        }

        // Gidiş: aynı gün, İstanbul kalkışlı, kalkışa en yakın olan
        let outCandidates = await byNumber(ours, day: day)
            .filter { $0.departure?.airport?.icao == InboundService.airport }
        guard let out = outCandidates.min(by: {
            abs((depRef($0) ?? .distantFuture).timeIntervalSince(ref)) < abs((depRef($1) ?? .distantFuture).timeIntervalSince(ref))
        }), let dest = out.arrival?.airport else { return nil }
        let outArrival = arrRef(out)

        // Dönüş: numara +1 / -1, varış meydanından İstanbul'a, gidişin varışından sonra
        var back: Flight? = nil
        let letters = String(ours.prefix { $0.isLetter })
        if let n = Int(ours.dropFirst(letters.count)) {
            for candidate in [n + 1, n - 1] where back == nil {
                var list: [Flight] = []
                for d in istanbulDays(ref, plus: 1) { list += await byNumber("\(letters)\(candidate)", day: d) }
                back = list
                    .filter { $0.departure?.airport?.icao == dest.icao && $0.arrival?.airport?.icao == InboundService.airport }
                    .filter { (depRef($0) ?? .distantPast) > (outArrival ?? ref) }
                    .min { (depRef($0) ?? .distantFuture) < (depRef($1) ?? .distantFuture) }
            }
        }

        return TurnInfo(
            destICAO: dest.icao ?? "",
            destIATA: dest.iata ?? "",
            destCity: dest.municipalityName ?? dest.shortName ?? "",
            outboundArrival: outArrival,
            returnFlight: back.map { ($0.number ?? "").replacingOccurrences(of: " ", with: "") },
            returnDeparture: back.flatMap(depRef),
            returnArrival: back.flatMap(arrRef)
        )
    }

    static func fetch(registration: String, before departure: Date?, stand: String) async -> InboundInfo? {
        guard let flights = await loadFlights(registration.uppercased(), around: departure) else { return nil }

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
            state.turn = await AeroDataBox.turn(registration: state.registration, flight: state.flight, around: state.eobt)
        }
        return state
    }
}
