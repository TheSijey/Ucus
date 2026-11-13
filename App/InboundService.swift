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
        let aircraft: Aircraft?
    }
    private struct Aircraft: Decodable {
        let reg: String?
        let model: String?
    }
    private struct Movement: Decodable {
        let airport: Airport?
        let scheduledTime: Time?
        let revisedTime: Time?
        let predictedTime: Time?
        let runwayTime: Time?
        let runway: String?
        let gate: String?
        let terminal: String?
    }
    private struct Airport: Decodable {
        let icao: String?
        let iata: String?
        let municipalityName: String?
        let shortName: String?
        let name: String?
        let timeZone: String?
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

    /// Kota dolunca (HTTP 429) bir süre hiç sorgu yapılmaz.
    /// Kota dolunca (HTTP 429) 30 dk sorgu yapılmaz. Eski sürümün 6 saatlik beklemesi geçersiz sayılır.
    static var quotaBlocked: Bool {
        guard let until = UserDefaults.standard.object(forKey: "aeroBlockedUntil") as? Date else { return false }
        let left = until.timeIntervalSinceNow
        return left > 0 && left <= 30 * 60
    }

    /// Elle yenileme ya da yeni takip: beklemeyi kaldır, hemen tekrar dene.
    static func clearQuotaBlock() {
        UserDefaults.standard.removeObject(forKey: "aeroBlockedUntil")
    }

    /// Yanıtlar diskte saklanır: uygulama kapanıp açılınca aynı sorgu tekrar yapılmaz.
    /// Geçmiş günlerin verisi değişmediği için 7 gün, bugünkü veriler `ttl` kadar geçerli.
    private static let cacheDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("aerodatabox")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func cacheFile(_ path: String) -> URL {
        cacheDir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    private static func isPastDay(_ path: String) -> Bool {
        guard let last = path.split(separator: "/").last.map(String.init),
              last.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let today = istanbulDays(Date()).first else { return false }
        return last < today
    }

    private static func decode(_ data: Data) -> [Flight]? { try? JSONDecoder().decode([Flight].self, from: data) }

    private static func request(path: String, ttl: TimeInterval = 600) async -> [Flight]? {
        let file = cacheFile(path)
        let maxAge = isPastDay(path) ? 7 * 86_400 : ttl
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let age = (attrs?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        let cached = (try? Data(contentsOf: file)).flatMap(decode)
        if let cached, age < maxAge { return cached }
        if quotaBlocked { return cached }

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
            return cached
        }
        if http.statusCode == 204 {
            try? Data("[]".utf8).write(to: file)
            return []
        }
        if http.statusCode == 429 {
            UserDefaults.standard.set(Date().addingTimeInterval(30 * 60), forKey: "aeroBlockedUntil")
            DebugLog.add("AeroDataBox kotası doldu (429); 30 dk sorgu yapılmayacak")
            return cached
        }
        guard http.statusCode == 200, let flights = decode(result.0) else {
            let body = String(data: result.0.prefix(120), encoding: .utf8) ?? ""
            DebugLog.add("AeroDataBox \(path): HTTP \(http.statusCode) \(body)")
            return cached
        }
        try? result.0.write(to: file)
        return flights
    }

    /// Dış meydandan kalkan uçuş (CDM'de yok): bilgiler AeroDataBox'tan.
    /// `day`: roster'daki UTC gün; yoksa en yakın (henüz kalkmamış ya da az önce kalkmış) sefer.
    static func outstation(flight raw: String, day: Date?) async -> FlightAttributes.ContentState? {
        let ours = normFlight(raw)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = utc.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let base = day ?? Date()
        // AeroDataBox yerel kalkış gününe göre arar: UTC gün ve bir sonraki/önceki gün
        let dates = [0, 1, -1].compactMap { utc.date(byAdding: .day, value: $0, to: base) }.map { fmt.string(from: $0) }

        func dep(_ f: Flight) -> Date? { f.departure?.revisedTime?.date ?? f.departure?.scheduledTime?.date }
        var candidates: [Flight] = []
        for d in dates {
            let list = (await request(path: "flights/number/\(ours)/\(d)", ttl: 900) ?? [])
                .filter { ($0.departure?.airport?.icao ?? InboundService.airport) != InboundService.airport && ($0.status ?? "") != "Canceled" }
            candidates += list
            if let day, candidates.contains(where: { dep($0).map { utc.isDate($0, inSameDayAs: day) } ?? false }) { break }
            if day == nil, candidates.contains(where: { (dep($0) ?? .distantPast) > Date().addingTimeInterval(-3 * 3600) }) { break }
        }
        let pick: Flight?
        if let day {
            pick = candidates.first { dep($0).map { utc.isDate($0, inSameDayAs: day) } ?? false }
        } else {
            pick = candidates.filter { (dep($0) ?? .distantPast) > Date().addingTimeInterval(-3 * 3600) }
                .min { (dep($0) ?? .distantFuture) < (dep($1) ?? .distantFuture) }
        }
        guard let f = pick, let from = f.departure?.airport, let std = dep(f) else { return nil }
        let to = f.arrival?.airport
        let arrival = f.arrival?.revisedTime?.date ?? f.arrival?.predictedTime?.date ?? f.arrival?.scheduledTime?.date
        let model = f.aircraft?.model ?? ""
        let type = model.split(separator: " ").last.map(String.init) ?? ""

        var state = FlightAttributes.ContentState(
            flight: ours, callsign: "", registration: f.aircraft?.reg ?? "", aircraftType: type,
            destination: to?.iata ?? "", gate: f.departure?.gate ?? "", stand: "", runway: f.departure?.runway ?? "",
            eobt: std, tobt: nil, tsat: nil, ctot: nil,
            signOn: std.addingTimeInterval(-3600), updatedAt: Date())
        state.origin = from.icao
        state.originIATA = from.iata
        state.originCity = from.municipalityName ?? from.shortName
        state.originTZ = from.timeZone
        state.turn = TurnInfo(destICAO: to?.icao ?? "", destIATA: to?.iata ?? "", destCity: to?.municipalityName ?? "",
                              outboundArrival: arrival, returnFlight: nil, returnDeparture: nil, returnArrival: nil)
        return state
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
        let list = await request(path: "flights/number/\(flight)/\(day)", ttl: 3600) ?? []
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

        // Varış meydanındaki gate: dönüş seferinin kalkış gate'i (uçak oraya park eder).
        // Bugünkü yayınlandıysa o, ayrıca son 3 günün geçmişi (günde bir kez sorgulanır).
        var history: [String] = []
        if let b = back, let num = b.number?.replacingOccurrences(of: " ", with: "") {
            history = await gateHistory(flight: num, from: dest.icao ?? "", before: ref)
        }

        var info = TurnInfo(
            destICAO: dest.icao ?? "",
            destIATA: dest.iata ?? "",
            destCity: dest.municipalityName ?? dest.shortName ?? "",
            outboundArrival: outArrival,
            returnFlight: back.map { ($0.number ?? "").replacingOccurrences(of: " ", with: "") },
            returnDeparture: back.flatMap(depRef),
            returnArrival: back.flatMap(arrRef)
        )
        info.destGateToday = back?.departure?.gate
        info.destGateHistory = history
        info.destRunwayHistory = await runwayHistory(flight: ours, to: dest.icao ?? "", before: ref)
        info.arrivalGateToday = out.arrival?.gate
        return info
    }

    private static var runwayCache: [String: (date: Date, runways: [String])] = [:]

    /// Gidiş seferinin son 3 günde varış meydanındaki iniş pistleri (en yeni önce).
    private static func runwayHistory(flight: String, to icao: String, before ref: Date) async -> [String] {
        let days = istanbulDays(ref.addingTimeInterval(-2 * 86_400), plus: 1)
        let key = flight + "|" + (days.last ?? "")
        if let c = runwayCache[key], Date().timeIntervalSince(c.date) < 86_400 { return c.runways }
        var list: [String] = []
        for d in days.reversed() {
            let flights = await request(path: "flights/number/\(flight)/\(d)") ?? []
            if let r = flights.first(where: { $0.arrival?.airport?.icao == icao })?.arrival?.runway, !r.isEmpty {
                list.append(r)
            }
        }
        runwayCache[key] = (Date(), list)
        return list
    }

    private static var gateCache: [String: (date: Date, gates: [String])] = [:]

    /// Dönüş seferinin son 3 gündeki kalkış gate'leri (en yeni önce).
    private static func gateHistory(flight: String, from icao: String, before ref: Date) async -> [String] {
        let days = istanbulDays(ref.addingTimeInterval(-2 * 86_400), plus: 1)   // 2 gün önce .. dün
        let key = flight + "|" + (days.last ?? "")
        if let c = gateCache[key], Date().timeIntervalSince(c.date) < 86_400 { return c.gates }
        var gates: [String] = []
        for d in days.reversed() {
            let list = await request(path: "flights/number/\(flight)/\(d)") ?? []
            if let g = list.first(where: { $0.departure?.airport?.icao == icao })?.departure?.gate, !g.isEmpty {
                gates.append(g)
            }
        }
        gateCache[key] = (Date(), gates)
        return gates
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
        // Gerçek saat gelmemiş ama tahmini park saati 30 dk'dan eski: uçak inmiş ve parkta kabul et.
        if info.parked == nil, let ep = info.estimatedPark, ep < Date().addingTimeInterval(-30 * 60) {
            if info.landed == nil { info.landed = info.estimatedLanding }
            info.parked = ep
            info.estimatedLanding = nil
            info.isAssumed = true
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
    /// İstanbul kalkışı CDM'den; CDM'de yoksa ve bir sefer numarasıysa dış meydan kalkışı olarak AeroDataBox'tan.
    /// `outstation`: zaten dış meydan uçuşu olduğu biliniyorsa (yenileme) CDM'ye hiç sorulmaz.
    static func load(query: String, plannedDay: Date? = nil, outstation: Bool = false) async throws -> FlightAttributes.ContentState {
        let q = CDMFetcher.normalize(query)
        let isFlightNumber = q.range(of: #"^[A-Z0-9]{2}\d{1,4}[A-Z]?$"#, options: .regularExpression) != nil
        if outstation, isFlightNumber, let s = await AeroDataBox.outstation(flight: q, day: plannedDay) {
            return ManualTimes.apply(s)
        }
        let state: FlightAttributes.ContentState
        do {
            state = try await CDMFetcher.shared.fetch(query: query)
        } catch {
            if let e = error as? CDMError, case .empty = e { throw e }
            if isFlightNumber, InboundService.rapidKey != nil,
               let s = await AeroDataBox.outstation(flight: q, day: plannedDay) {
                DebugLog.add("CDM'de yok, dış meydan kalkışı: \(s.flight) \(s.originCode)")
                return ManualTimes.apply(s)
            }
            throw error
        }
        return await completeIstanbul(state)
    }

    private static func completeIstanbul(_ input: FlightAttributes.ContentState) async -> FlightAttributes.ContentState {
        var state = input
        state.inbound = await InboundService.fetch(registration: state.registration,
                                                   before: state.eobt, stand: state.stand)
        if InboundService.rapidKey != nil, !state.registration.isEmpty {
            state.turn = await AeroDataBox.turn(registration: state.registration, flight: state.flight, around: state.eobt)
        }
        return state
    }
}
