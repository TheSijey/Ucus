import SwiftUI
import Charts
import LocalAuthentication
import UserNotifications

// MARK: - Bulut ayarı (web sürümüyle aynı Firebase projesi)

enum Config {
    static let apiKey = "AIzaSyBd4INdzdZEefvUFR0BAsVwJ9cE7taWg2w"
    static let projectId = "varliklar-46b7e"
}

// MARK: - Tema

extension Color {
    init(light: Color, dark: Color) {
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

enum Theme {
    static let bg = Color(light: Color(red: 0.949, green: 0.953, blue: 0.969), dark: Color(red: 0.059, green: 0.067, blue: 0.086))
    static let card = Color(light: .white, dark: Color(red: 0.102, green: 0.114, blue: 0.149))
    static let line = Color(light: Color(red: 0.894, green: 0.902, blue: 0.933), dark: Color(red: 0.165, green: 0.180, blue: 0.231))
    static let muted = Color(light: Color(red: 0.42, green: 0.44, blue: 0.50), dark: Color(red: 0.565, green: 0.592, blue: 0.667))
    static let pri = Color(light: Color(red: 0.231, green: 0.310, blue: 0.847), dark: Color(red: 0.482, green: 0.549, blue: 1.0))
}

struct Seg<T: Hashable & Identifiable>: View {
    let items: [T]
    let title: (T) -> String
    @Binding var sel: T
    var bg: Color = Theme.card

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { it in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { sel = it }
                } label: {
                    Text(title(it))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(sel == it ? Color.white : Theme.muted)
                        .background(sel == it ? Theme.pri : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(bg, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Chips: View {
    let items: [String]
    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { it in
                        Button { onPick(it) } label: {
                            Text(it)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected == it ? Color.white : Color.primary)
                                .background(selected == it ? Theme.pri : Theme.line, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Dil (Türkçe / English)

func isEnglish() -> Bool {
    let pref: String = UserDefaults.standard.string(forKey: "lang") ?? "auto"
    if pref == "en" { return true }
    if pref == "tr" { return false }
    let first: String = Locale.preferredLanguages.first ?? "tr"
    return !first.hasPrefix("tr")
}

func L(_ tr: String, _ en: String) -> String {
    isEnglish() ? en : tr
}

// MARK: - Model

enum AssetGroup: String, CaseIterable, Identifiable {
    case gold = "Altın", fx = "Döviz", tl = "TL", stock = "Hisse"
    case crypto = "Kripto", fund = "Fon", deposit = "Vadeli", other = "Diğer", debt = "Borç"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gold: return L("Altın", "Gold")
        case .fx: return L("Döviz", "Foreign currency")
        case .tl: return "TL"
        case .stock: return L("Hisse", "Stocks")
        case .crypto: return L("Kripto", "Crypto")
        case .fund: return L("Fon", "Funds")
        case .deposit: return L("Vadeli", "Time deposits")
        case .other: return L("Diğer", "Other")
        case .debt: return L("Borç", "Debt")
        }
    }

    /// Hiç kaydı olmasa da özette gösterilen gruplar
    var alwaysShown: Bool { self == .gold || self == .fx || self == .tl }

    var color: Color {
        switch self {
        case .gold: return Color(red: 0.85, green: 0.65, blue: 0.08)
        case .fx: return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .tl: return Color(red: 0.23, green: 0.44, blue: 0.83)
        case .stock: return Color(red: 0.89, green: 0.30, blue: 0.52)
        case .other: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .crypto: return Color(red: 0.97, green: 0.58, blue: 0.10)
        case .fund: return Color(red: 0.05, green: 0.65, blue: 0.64)
        case .deposit: return Color(red: 0.39, green: 0.40, blue: 0.95)
        case .debt: return Color(red: 0.84, green: 0.27, blue: 0.27)
        }
    }
}

enum Kind: String, Codable, CaseIterable, Identifiable {
    case tl = "TL", usd = "USD", eur = "EUR", gbp = "GBP"
    case gold = "Altın (gr)"
    case bankGold = "Banka gram altını"
    case yarimGram = "Yarım gram", ceyrek = "Çeyrek", yarim = "Yarım", tam = "Tam", cumhuriyet = "Cumhuriyet"
    case stock = "Hisse senedi"
    case crypto = "Kripto", fund = "Fon", deposit = "Vadeli hesap", debt = "Borç"
    case custom = "Kendi türüm"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gold: return L("Gram altın (fiziki)", "Gold gram (physical)")
        case .bankGold: return L("Gram altın (banka)", "Gold gram (bank)")
        case .usd: return L("Dolar (USD)", "US dollar (USD)")
        case .eur: return L("Euro (EUR)", "Euro (EUR)")
        case .gbp: return L("Sterlin (GBP)", "Pound sterling (GBP)")
        case .ceyrek: return L("Çeyrek altın", "Quarter gold coin")
        case .yarim: return L("Yarım altın", "Half gold coin")
        case .tam: return L("Tam altın", "Full gold coin")
        case .cumhuriyet: return L("Cumhuriyet altını", "Republic gold coin")
        case .stock: return L("Hisse senedi (otomatik fiyat)", "Stock (auto price)")
        case .crypto: return L("Kripto para (otomatik fiyat)", "Crypto (auto price)")
        case .fund: return L("Yatırım fonu", "Investment fund")
        case .deposit: return L("Vadeli hesap (faizli)", "Time deposit (interest-bearing)")
        case .debt: return L("Borç", "Debt")
        case .custom: return L("＋ Kendi türüm (araç, ev...)", "+ Custom type (car, house...)")
        case .yarimGram: return L("Yarım gram altın", "Half gram gold")
        default: return rawValue
        }
    }

    /// Bulutta (web sürümüyle ortak) kullanılan anahtar
    var key: String {
        switch self {
        case .tl: return "tl"
        case .usd: return "usd"
        case .eur: return "eur"
        case .gbp: return "gbp"
        case .gold: return "gram"
        case .bankGold: return "bankGram"
        case .yarimGram: return "yarimGram"
        case .ceyrek: return "ceyrek"
        case .yarim: return "yarim"
        case .tam: return "tam"
        case .cumhuriyet: return "cumhuriyet"
        case .stock: return "stock"
        case .crypto: return "crypto"
        case .fund: return "fund"
        case .deposit: return "deposit"
        case .debt: return "debt"
        case .custom: return "custom"
        }
    }

    var isPriced: Bool { self == .stock || self == .crypto || self == .fund }

    var shortName: String {
        switch self {
        case .stock: return L("Hisse", "Stock")
        case .crypto: return L("Kripto", "Crypto")
        case .fund: return L("Fon", "Fund")
        case .deposit: return "Vadeli hesap"
        case .debt: return L("Borç", "Debt")
        default: return title
        }
    }

    static func fromKey(_ k: String) -> Kind? {
        Kind.allCases.first { $0.key == k }
    }

    var group: AssetGroup {
        switch self {
        case .tl: return .tl
        case .usd, .eur, .gbp: return .fx
        case .stock: return .stock
        case .crypto: return .crypto
        case .fund: return .fund
        case .deposit: return .deposit
        case .debt: return .debt
        case .custom: return .other
        default: return .gold
        }
    }

    /// Birim başına has (saf) altın gramı. Altın olmayanlar için nil.
    var goldGrams: Double? {
        switch self {
        case .gold, .bankGold: return 1
        case .yarimGram: return 0.5
        case .ceyrek: return 1.75 * 0.916
        case .yarim: return 3.5 * 0.916
        case .tam: return 7.0 * 0.916
        case .cumhuriyet: return 7.2 * 0.916
        default: return nil
        }
    }

    var unitLabel: String {
        unit == "adet" ? L("adet", "pcs") : unit
    }

    var unit: String {
        switch self {
        case .tl, .usd, .eur, .gbp, .custom, .deposit, .debt: return ""
        case .gold, .bankGold: return "gr"
        default: return "adet"
        }
    }

    static func fromCur(_ c: String) -> Kind {
        switch c {
        case "usd": return .usd
        case "eur": return .eur
        case "gbp": return .gbp
        default: return .tl
        }
    }
}

struct Asset: Identifiable, Codable {
    var id: String
    var location: String
    var owner: String
    var kind: Kind
    var amount: Double
    var typeName: String
    var cur: String   // "Kendi türüm" ve "Hisse" için para birimi: tl, usd, eur, gbp
    var symbol: String   // yalnızca hisse için (örn. THYAO.IS)
    var price: Double    // yalnızca hisse için: son bilinen birim fiyat (cur cinsinden)
    var cost: Double     // isteğe bağlı: toplam alış maliyeti (TL). 0 = girilmemiş
    var order: Int       // liste sırası (küçük olan üstte)
    var rate: Double     // yalnızca vadeli hesap: yıllık faiz (%)
    var start: String    // yalnızca vadeli hesap: başlangıç (yyyy-MM-dd)
    var maturity: String // yalnızca vadeli hesap: vade tarihi (yyyy-MM-dd)

    init(id: String = UUID().uuidString.lowercased(), location: String, owner: String,
         kind: Kind, amount: Double, typeName: String = "", cur: String = "tl",
         symbol: String = "", price: Double = 0, cost: Double = 0, order: Int = 0,
         rate: Double = 0, start: String = "", maturity: String = "") {
        self.id = id
        self.location = location
        self.owner = owner
        self.kind = kind
        self.amount = amount
        self.typeName = typeName
        self.cur = cur
        self.symbol = symbol
        self.price = price
        self.cost = cost
        self.order = order
        self.rate = rate
        self.start = start
        self.maturity = maturity
    }

    enum CodingKeys: String, CodingKey { case id, location, owner, kind, amount, typeName, cur, symbol, price, cost, order, rate, start, maturity }

    // Eski kayıtlarda typeName, cur, symbol ve price yok; eksik alanlar varsayılanla doldurulur.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString.lowercased()
        location = (try? c.decode(String.self, forKey: .location)) ?? ""
        owner = (try? c.decode(String.self, forKey: .owner)) ?? ""
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .tl
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        typeName = (try? c.decode(String.self, forKey: .typeName)) ?? ""
        cur = (try? c.decode(String.self, forKey: .cur)) ?? "tl"
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? ""
        price = (try? c.decode(Double.self, forKey: .price)) ?? 0
        cost = (try? c.decode(Double.self, forKey: .cost)) ?? 0
        order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        rate = (try? c.decode(Double.self, forKey: .rate)) ?? 0
        start = (try? c.decode(String.self, forKey: .start)) ?? ""
        maturity = (try? c.decode(String.self, forKey: .maturity)) ?? ""
    }

    var displayName: String {
        switch kind {
        case .custom: return typeName.isEmpty ? L("Diğer", "Other") : typeName
        case .stock: return typeName.isEmpty ? (symbol.isEmpty ? L("Hisse", "Stock") : symbol) : typeName
        case .crypto, .fund, .deposit, .debt:
            if !typeName.isEmpty { return typeName }
            if !symbol.isEmpty { return symbol }
            return kind.shortName
        default: return kind.title
        }
    }
}

struct Rates: Codable {
    var tryPerUSD: Double
    var eurPerUSD: Double
    var gbpPerUSD: Double
    var goldUSDPerGram: Double
    var updated: Date
}

struct Session: Codable {
    var idToken: String
    var refreshToken: String
    var expires: Date
    var email: String
    var uid: String
}

struct Slice: Identifiable {
    let name: String
    let value: Double
    let color: Color
    var id: String { name }
}

struct Bucket: Identifiable {
    let name: String
    let items: [Asset]
    var id: String { name }
}

struct AddRequest: Identifiable {
    let id = UUID()
    var location: String = ""
    var owner: String = ""
}

enum CloudError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

let palette: [Color] = [.indigo, .teal, .orange, .pink, .purple, .mint, .brown, .cyan]

// MARK: - Sayı yardımcıları (1.250,50 biçimi)

func numTR(_ s: String) -> Double {
    Double(s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
}

func formatMoneyInput(_ s: String, allowNeg: Bool) -> String {
    var v = s.filter { "0123456789,-".contains($0) }
    let neg = allowNeg && v.hasPrefix("-")
    v = v.replacingOccurrences(of: "-", with: "")
    let parts = v.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    var intPart = parts.first ?? ""
    while intPart.count > 1 && intPart.hasPrefix("0") { intPart.removeFirst() }
    var grouped = ""
    for (i, ch) in intPart.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { grouped.append(".") }
        grouped.append(ch)
    }
    grouped = String(grouped.reversed())
    var out = grouped
    if parts.count > 1 { out += "," + String(parts.dropFirst().joined().prefix(4)) }
    return (neg ? "-" : "") + out
}

func fmtIn(_ x: Double) -> String {
    var s = String(format: "%.4f", x)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return formatMoneyInput(s.replacingOccurrences(of: ".", with: ","), allowNeg: false)
}

// MARK: - Hisse yardımcıları

struct StockHit: Identifiable {
    let symbol: String
    let name: String
    let exchange: String
    var id: String { symbol }
}

struct Quote {
    let price: Double
    let cur: String   // tl, usd, eur, gbp
}

struct HeldStock: Identifiable {
    let symbol: String
    let name: String
    let price: Double
    let cur: String
    let qty: Double
    let group: AssetGroup
    var id: String { symbol }
}

struct HistPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

let dayFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

func parseDay(_ s: String) -> Date? { dayFmt.date(from: s) }

/// Başlangıçtan bugüne (vadeyle sınırlı) geçen gün
func depositDays(_ a: Asset) -> Double {
    guard let st = parseDay(a.start) else { return 0 }
    var end = Date()
    if let m = parseDay(a.maturity), m < end { end = m }
    return max(0, end.timeIntervalSince(st) / 86400)
}

/// Başlangıçtan vadeye toplam gün
func depositTermDays(_ a: Asset) -> Double {
    guard let st = parseDay(a.start), let m = parseDay(a.maturity), m > st else { return 0 }
    return m.timeIntervalSince(st) / 86400
}

func daysLeft(_ a: Asset) -> Int? {
    guard let m = parseDay(a.maturity) else { return nil }
    return Int(ceil(m.timeIntervalSinceNow / 86400))
}

func trDay(_ s: String) -> String {
    guard let d = parseDay(s) else { return s }
    let f = DateFormatter()
    f.dateFormat = "dd.MM.yyyy"
    return f.string(from: d)
}

func depositSubtitle(_ a: Asset, base: String) -> String {
    var t: String = base
    if a.rate > 0 { t += " · %" + fmtIn(a.rate) }
    if parseDay(a.maturity) != nil {
        t += L(" · vade ", " · maturity ") + trDay(a.maturity)
        if let d = daysLeft(a) {
            t += d > 0 ? L(" (\(d) gün kaldı)", " (\(d) days left)") : L(" (vade doldu)", " (matured)")
        }
    }
    return t
}

func csvEsc(_ x: String) -> String {
    if x.contains(";") || x.contains("\"") || x.contains("\n") {
        return "\"" + x.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return x
}

func csvNum(_ x: Double) -> String {
    String(format: "%.2f", x).replacingOccurrences(of: ".", with: ",")
}

struct GoldLine: Identifiable {
    let kind: Kind
    let qty: Double
    let usd: Double
    var id: String { kind.rawValue }
}

func curSymbol(_ c: String) -> String {
    ["tl": "₺", "usd": "$", "eur": "€", "gbp": "£"][c] ?? ""
}

func qtyText(_ q: Double) -> String {
    q.formatted(.number.precision(.fractionLength(0...2)))
}

func shortSymbol(_ s: String) -> String {
    s.replacingOccurrences(of: ".IS", with: "")
}

func priceText(_ p: Double, _ cur: String) -> String {
    if p <= 0 { return "—" }
    let n: String = p.formatted(.number.precision(.fractionLength(2)))
    return curSymbol(cur) + n
}

func goldQtyText(_ g: GoldLine, hidden: Bool) -> String {
    if hidden { return "••••" }
    let q: String = qtyText(g.qty)
    return q + " " + g.kind.unitLabel
}

func heldSubtitle(_ h: HeldStock) -> String {
    let s: String = shortSymbol(h.symbol)
    let q: String = qtyText(h.qty)
    return s + " · " + q + L(" adet", " pcs")
}

func hitSubtitle(_ h: StockHit) -> String {
    if h.exchange.isEmpty { return h.symbol }
    return h.symbol + " · " + h.exchange
}

func debtSubtitle(_ a: Asset, base: String) -> String {
    var t: String = base + L(" · borç", " · debt")
    if parseDay(a.maturity) != nil {
        t += L(" · son gün ", " · due ") + trDay(a.maturity)
        if let d = daysLeft(a) {
            if d > 0 { t += L(" (\(d) gün kaldı)", " (\(d) days left)") }
            else { t += L(" (süresi geçti)", " (overdue)") }
        }
    }
    return t
}

func rowSubtitle(_ a: Asset, base: String) -> String {
    switch a.kind {
    case .stock:
        return a.symbol.isEmpty ? base : base + " · " + shortSymbol(a.symbol)
    case .crypto:
        return a.symbol.isEmpty ? base : base + " · " + a.symbol
    case .deposit:
        return depositSubtitle(a, base: base)
    case .debt:
        return debtSubtitle(a, base: base)
    default:
        return base
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var assets: [Asset] = [] { didSet { save(); Task { await Reminders.sync(assets) } } }
    @Published var history: [String: Double] = [:] { didSet { UserDefaults.standard.set(history, forKey: "hist") } }
    @Published var rates: Rates?
    @Published var loading = false
    @Published var error: String?
    @Published var syncError: String?
    @Published var stockError: String?
    @Published var stockUpdated: Date?
    @Published var hidden: Bool { didSet { UserDefaults.standard.set(hidden, forKey: "hide") } }
    @Published var netHidden: Bool
    @Published var netHideLaunch: Bool { didSet { UserDefaults.standard.set(netHideLaunch, forKey: "netHideLaunch") } }
    @Published var curRaw: String { didSet { UserDefaults.standard.set(curRaw, forKey: "cur") } }
    @Published var session: Session? { didSet { saveSession() } }

    private var pushTasks: [String: Task<Void, Never>] = [:]

    var cur: Kind { Kind(rawValue: curRaw) ?? .tl }
    var signedIn: Bool { session != nil }

    init() {
        hidden = UserDefaults.standard.bool(forKey: "hide")
        let launchHide: Bool = UserDefaults.standard.bool(forKey: "netHideLaunch")
        netHideLaunch = launchHide
        netHidden = launchHide
        curRaw = UserDefaults.standard.string(forKey: "cur") ?? Kind.tl.rawValue
        if let d = UserDefaults.standard.data(forKey: "assets"),
           let a = try? JSONDecoder().decode([Asset].self, from: d) { assets = a }
        if let h = UserDefaults.standard.dictionary(forKey: "hist") as? [String: Double] { history = h }
        if let d = UserDefaults.standard.data(forKey: "rates"),
           let r = try? JSONDecoder().decode(Rates.self, from: d) { rates = r }
        if let d = UserDefaults.standard.data(forKey: "session"),
           let s = try? JSONDecoder().decode(Session.self, from: d) { session = s }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(assets) {
            UserDefaults.standard.set(d, forKey: "assets")
        }
    }

    private func saveSession() {
        if let s = session, let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: "session")
        } else {
            UserDefaults.standard.removeObject(forKey: "session")
        }
    }

    // MARK: Kurlar

    func refresh() async {
        loading = true
        error = nil
        defer { loading = false }
        struct FX: Decodable { let rates: [String: Double] }
        struct Gold: Decodable { let price: Double }
        do {
            let (fxData, _) = try await URLSession.shared.data(from: URL(string: "https://open.er-api.com/v6/latest/USD")!)
            let (goldData, _) = try await URLSession.shared.data(from: URL(string: "https://api.gold-api.com/price/XAU")!)
            let fx = try JSONDecoder().decode(FX.self, from: fxData)
            let gold = try JSONDecoder().decode(Gold.self, from: goldData)
            guard let t = fx.rates["TRY"], let e = fx.rates["EUR"], let p = fx.rates["GBP"] else {
                throw URLError(.badServerResponse)
            }
            // 1 troy ons = 31.1035 gram
            let r = Rates(tryPerUSD: t, eurPerUSD: e, gbpPerUSD: p,
                          goldUSDPerGram: gold.price / 31.1035, updated: Date())
            rates = r
            if let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: "rates") }
        } catch {
            self.error = L("Kurlar alınamadı, son kayıtlı kurlar kullanılıyor.", "Could not fetch rates; using the last saved rates.")
        }
    }

    func reloadAll() async {
        await refresh()
        await pull()
        await refreshStocks()
        await pullHistory()
        await snapHistory()
    }

    // MARK: Hisse fiyatları (Yahoo Finance, ~15 dk gecikmeli, resmi olmayan kaynak)

    private func yahooGET(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CloudError.message("HTTP \(http.statusCode)")
        }
        return data
    }

    func searchStocks(_ q: String) async -> [StockHit] {
        let text = q.trimmingCharacters(in: .whitespaces)
        if text.count < 2 { return [] }
        var comps = URLComponents(string: "https://query2.finance.yahoo.com/v1/finance/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "quotesCount", value: "10"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "lang", value: "tr-TR"),
            URLQueryItem(name: "region", value: "TR")
        ]
        guard let url = comps.url,
              let data = try? await yahooGET(url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = o["quotes"] as? [[String: Any]] else { return [] }
        var out: [StockHit] = []
        for qd in quotes {
            guard let sym = qd["symbol"] as? String,
                  let type = qd["quoteType"] as? String,
                  type == "EQUITY" || type == "ETF" else { continue }
            let name = (qd["longname"] as? String) ?? (qd["shortname"] as? String) ?? sym
            let ex = (qd["exchDisp"] as? String) ?? (qd["exchange"] as? String) ?? ""
            out.append(StockHit(symbol: sym, name: name, exchange: ex))
        }
        return out
    }

    func fetchQuote(_ symbol: String) async -> Quote? {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=1d&range=1d"),
              let data = try? await yahooGET(url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = o["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any],
              var price = meta["regularMarketPrice"] as? Double,
              let c = meta["currency"] as? String else { return nil }
        let cur: String
        switch c {
        case "TRY": cur = "tl"
        case "USD": cur = "usd"
        case "EUR": cur = "eur"
        case "GBP": cur = "gbp"
        case "GBp", "GBX":
            cur = "gbp"
            price /= 100
        default: return nil
        }
        return Quote(price: price, cur: cur)
    }

    func refreshStocks() async {
        await refreshStockQuotes()
        await refreshCrypto()
    }

    func searchCrypto(_ q: String) async -> [StockHit] {
        let text = q.trimmingCharacters(in: .whitespaces)
        if text.count < 2 { return [] }
        guard let enc = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.coingecko.com/api/v3/search?query=\(enc)"),
              let data = try? await yahooGET(url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let coins = o["coins"] as? [[String: Any]] else { return [] }
        var out: [StockHit] = []
        for c in coins.prefix(8) {
            guard let id = c["id"] as? String else { continue }
            let name = (c["name"] as? String) ?? id
            let sym = ((c["symbol"] as? String) ?? "").uppercased()
            out.append(StockHit(symbol: id, name: name, exchange: sym))
        }
        return out
    }

    func fetchCryptoPrices(_ ids: [String]) async -> [String: Double] {
        let list = ids.joined(separator: ",")
        guard let enc = list.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(enc)&vs_currencies=try"),
              let data = try? await yahooGET(url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        for id in ids {
            if let m = o[id] as? [String: Any], let p = m["try"] as? Double, p > 0 { out[id] = p }
        }
        return out
    }

    func refreshCrypto() async {
        let ids = Array(Set(assets.filter { $0.kind == .crypto && !$0.symbol.isEmpty }.map(\.symbol)))
        if ids.isEmpty { return }
        let prices = await fetchCryptoPrices(ids)
        for a in assets where a.kind == .crypto {
            guard let p = prices[a.symbol] else { continue }
            if abs(a.price - p) > 0.000001 || a.cur != "tl" {
                var n = a
                n.price = p
                n.cur = "tl"
                upsert(n)
            }
        }
    }

    func refreshStockQuotes() async {
        let symbols = Set(assets.filter { $0.kind == .stock && !$0.symbol.isEmpty }.map(\.symbol))
        if symbols.isEmpty { stockError = nil; return }
        var quotes: [String: Quote] = [:]
        for s in symbols {
            if let q = await fetchQuote(s) { quotes[s] = q }
        }
        if quotes.isEmpty {
            stockError = L("Hisse fiyatları alınamadı, son kayıtlı fiyatlar kullanılıyor.", "Could not fetch stock prices; using the last saved prices.")
            return
        }
        stockError = quotes.count < symbols.count ? L("Bazı hisselerin fiyatı alınamadı.", "Some stock prices could not be fetched.") : nil
        stockUpdated = Date()
        for a in assets where a.kind == .stock {
            guard let q = quotes[a.symbol] else { continue }
            if abs(a.price - q.price) > 0.00001 || a.cur != q.cur {
                var n = a
                n.price = q.price
                n.cur = q.cur
                upsert(n)
            }
        }
    }

    var heldStocks: [HeldStock] {
        let st = assets.filter { $0.kind.isPriced && !$0.symbol.isEmpty }
        return Dictionary(grouping: st, by: \.symbol)
            .map { sym, items in
                let f = items[0]
                return HeldStock(symbol: sym, name: f.typeName.isEmpty ? sym : f.typeName,
                                 price: f.price, cur: f.cur, qty: items.reduce(0) { $0 + $1.amount },
                                 group: f.kind.group)
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: Altın toplamları, kâr/zarar, sıralama

    func goldLines() -> [GoldLine] {
        let kinds: [Kind] = [.gold, .bankGold, .yarimGram, .ceyrek, .yarim, .tam, .cumhuriyet]
        return kinds.compactMap { k in
            let items = assets.filter { $0.kind == k }
            let qty = items.reduce(0) { $0 + $1.amount }
            return qty > 0 ? GoldLine(kind: k, qty: qty, usd: usdSum(items)) : nil
        }
    }

    /// Alış maliyeti girilmiş varlıkların toplam kâr/zararı (dolar cinsinden); hiç maliyet yoksa nil
    func totalPLUSD() -> Double? {
        let withCost = assets.filter { $0.cost > 0 }
        guard !withCost.isEmpty, let r = rates else { return nil }
        return withCost.reduce(0) { $0 + usd($1) - $1.cost / r.tryPerUSD }
    }

    func plUSD(_ a: Asset) -> Double? {
        guard a.cost > 0, let r = rates else { return nil }
        return usd(a) - a.cost / r.tryPerUSD
    }

    /// Kâr/zarar yüzdesi (maliyete göre)
    func plPct(_ a: Asset) -> Double? {
        guard a.cost > 0, let r = rates else { return nil }
        let c: Double = a.cost / r.tryPerUSD
        return (usd(a) - c) / c * 100
    }

    /// Bir birimin güncel TL fiyatı
    func unitTL(_ a: Asset) -> Double {
        guard let r = rates else { return 0 }
        var one = a
        one.amount = 1
        return usd(one) * r.tryPerUSD
    }

    /// Maliyeti girilmiş varlıkların toplam maliyeti (dolar)
    func totalCostUSD() -> Double {
        guard let r = rates else { return 0 }
        return assets.filter { $0.cost > 0 }.reduce(0) { $0 + $1.cost / r.tryPerUSD }
    }

    /// Yalnızca altın için kâr/zarar ve maliyet (dolar)
    func goldPL() -> (pl: Double, cost: Double)? {
        guard let r = rates else { return nil }
        let items: [Asset] = assets.filter { $0.cost > 0 && $0.kind.group == .gold }
        if items.isEmpty { return nil }
        let cost: Double = items.reduce(0) { $0 + $1.cost / r.tryPerUSD }
        let value: Double = usdSum(items)
        return (value - cost, cost)
    }

    func moveAsset(_ draggedID: String, onto targetID: String, in bucketItems: [Asset]) {
        guard draggedID != targetID,
              let from = bucketItems.firstIndex(where: { $0.id == draggedID }),
              let to = bucketItems.firstIndex(where: { $0.id == targetID }) else { return }
        var arr = bucketItems
        let item = arr.remove(at: from)
        arr.insert(item, at: to)
        let base = bucketItems.map(\.order).min() ?? 0
        for (i, a) in arr.enumerated() {
            guard let cur = assets.first(where: { $0.id == a.id }) else { continue }
            if cur.order != base + i {
                var n = cur
                n.order = base + i
                upsert(n, delay: 0.3)
            }
        }
    }

    // MARK: Bulut (Firebase REST)

    private func send(_ url: URL, method: String, body: Data?, contentType: String?, token: String?) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if let ct = contentType { req.setValue(ct, forHTTPHeaderField: "Content-Type") }
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var msg = "HTTP \(http.statusCode)"
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let e = o["error"] as? [String: Any],
               let m = e["message"] as? String {
                msg = m
            }
            throw CloudError.message(msg)
        }
        return data
    }

    static let mailDomain = "@varlik.app"

    func toMail(_ u: String) -> String {
        let t = u.trimmingCharacters(in: .whitespaces)
        return t.contains("@") ? t : t.lowercased() + Store.mailDomain
    }

    func shownName(_ email: String) -> String {
        email.hasSuffix(Store.mailDomain) ? String(email.dropLast(Store.mailDomain.count)) : email
    }

    private func authCall(_ endpoint: String, user: String, password: String) async throws {
        let mail = toMail(user)
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:\(endpoint)?key=\(Config.apiKey)")!
        let payload: [String: Any] = ["email": mail, "password": password, "returnSecureToken": true]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send(url, method: "POST", body: body, contentType: "application/json", token: nil)
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["idToken"] as? String,
              let rt = o["refreshToken"] as? String,
              let uid = o["localId"] as? String else {
            throw CloudError.message(L("Giriş yapılamadı", "Could not sign in"))
        }
        let secs = Double(o["expiresIn"] as? String ?? "3600") ?? 3600
        session = Session(idToken: id, refreshToken: rt, expires: Date().addingTimeInterval(secs), email: mail, uid: uid)
        syncError = nil
        await pull()
        await migrateLegacy()
        await refreshStocks()
    }

    func signIn(user: String, password: String) async throws {
        try await authCall("signInWithPassword", user: user, password: password)
    }

    func signUp(user: String, password: String) async throws {
        try await authCall("signUp", user: user, password: password)
    }

    // Eski ortak koleksiyondaki kayıtları, hesap boşsa bir kez kendi alanına kopyalar. Eskisi silinmez.
    func migrateLegacy() async {
        guard let s = session, assets.isEmpty else { return }
        let flag = "mig_" + s.uid
        if UserDefaults.standard.bool(forKey: flag) { return }
        do {
            let t = try await token()
            let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(Config.projectId)/databases/(default)/documents/assets?pageSize=300")!
            let data = try await send(url, method: "GET", body: nil, contentType: nil, token: t)
            let o = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            var found: [Asset] = []
            for d in (o["documents"] as? [[String: Any]]) ?? [] {
                if let a = parseDoc(d) { found.append(a) }
            }
            if found.isEmpty { return }
            assets = found
            for a in found { await push(a) }
            UserDefaults.standard.set(true, forKey: flag)
        } catch {
            // Eski koleksiyona izin yoksa (yeni hesap) sessizce geç
        }
    }

    func deleteAccount() async {
        guard signedIn else { return }
        do {
            let t = try await token()
            for a in assets {
                _ = try? await send(docURL(a.id), method: "DELETE", body: nil, contentType: nil, token: t)
            }
            let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=\(Config.apiKey)")!
            let body = try JSONSerialization.data(withJSONObject: ["idToken": t])
            _ = try await send(url, method: "POST", body: body, contentType: "application/json", token: nil)
            signOut()
        } catch {
            syncError = L("Hesap silinemedi: \(error.localizedDescription)", "Could not delete account: \(error.localizedDescription)")
        }
    }

    func signOut() {
        pushTasks.values.forEach { $0.cancel() }
        pushTasks = [:]
        session = nil
        assets = []
        history = [:]
        syncError = nil
    }

    func freshToken() async throws -> String { try await token() }

    private func token() async throws -> String {
        guard var s = session else { throw CloudError.message(L("Giriş gerekli", "Sign-in required")) }
        if s.expires.timeIntervalSinceNow < 120 {
            let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Config.apiKey)")!
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let rt = s.refreshToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? s.refreshToken
            let form = "grant_type=refresh_token&refresh_token=\(rt)"
            let data = try await send(url, method: "POST", body: form.data(using: .utf8),
                                      contentType: "application/x-www-form-urlencoded", token: nil)
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = o["id_token"] as? String,
                  let newRT = o["refresh_token"] as? String else {
                throw CloudError.message(L("Oturum yenilenemedi", "Session could not be renewed"))
            }
            let secs = Double(o["expires_in"] as? String ?? "3600") ?? 3600
            s.idToken = id
            s.refreshToken = newRT
            s.expires = Date().addingTimeInterval(secs)
            session = s
        }
        return s.idToken
    }

    private var assetsBase: String {
        let uid = session?.uid ?? "none"
        return "https://firestore.googleapis.com/v1/projects/\(Config.projectId)/databases/(default)/documents/users/\(uid)/assets"
    }

    private func docURL(_ id: String) -> URL {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "\(assetsBase)/\(enc)")!
    }

    private func fields(_ a: Asset) -> [String: Any] {
        [
            "location": ["stringValue": a.location],
            "owner": ["stringValue": a.owner],
            "kind": ["stringValue": a.kind.key],
            "typeName": ["stringValue": a.typeName],
            "cur": ["stringValue": a.cur],
            "amount": ["doubleValue": a.amount],
            "symbol": ["stringValue": a.symbol],
            "price": ["doubleValue": a.price],
            "cost": ["doubleValue": a.cost],
            "order": ["integerValue": String(a.order)],
            "rate": ["doubleValue": a.rate],
            "start": ["stringValue": a.start],
            "maturity": ["stringValue": a.maturity]
        ]
    }

    private func parseDoc(_ d: [String: Any]) -> Asset? {
        guard let name = d["name"] as? String,
              let f = d["fields"] as? [String: Any] else { return nil }
        let id = String(name.split(separator: "/").last ?? "")
        if id.isEmpty { return nil }
        func str(_ k: String) -> String {
            ((f[k] as? [String: Any])?["stringValue"] as? String) ?? ""
        }
        func num(_ k: String) -> Double {
            guard let m = f[k] as? [String: Any] else { return 0 }
            if let dv = m["doubleValue"] as? Double { return dv }
            if let iv = m["integerValue"] as? String, let x = Double(iv) { return x }
            if let iv = m["integerValue"] as? Int { return Double(iv) }
            return 0
        }
        let kind = Kind.fromKey(str("kind")) ?? .tl
        let curStr = str("cur")
        let cur = ["tl", "usd", "eur", "gbp"].contains(curStr) ? curStr : "tl"
        return Asset(id: id, location: str("location"), owner: str("owner"),
                     kind: kind, amount: num("amount"), typeName: str("typeName"), cur: cur,
                     symbol: str("symbol"), price: num("price"), cost: num("cost"), order: Int(num("order")),
                     rate: num("rate"), start: str("start"), maturity: str("maturity"))
    }

    private func isCancel(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let u = error as? URLError, u.code == .cancelled { return true }
        return error.localizedDescription.lowercased() == "canceled" || error.localizedDescription.lowercased() == "cancelled"
    }

    func pull() async {
        guard signedIn else { return }
        do {
            let t = try await token()
            var all: [Asset] = []
            var pageToken: String? = nil
            repeat {
                var comps = URLComponents(string: assetsBase)!
                var items = [URLQueryItem(name: "pageSize", value: "300")]
                if let p = pageToken { items.append(URLQueryItem(name: "pageToken", value: p)) }
                comps.queryItems = items
                let data = try await send(comps.url!, method: "GET", body: nil, contentType: nil, token: t)
                let o = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                for d in (o["documents"] as? [[String: Any]]) ?? [] {
                    if let a = parseDoc(d) { all.append(a) }
                }
                pageToken = o["nextPageToken"] as? String
            } while pageToken != nil

            // Henüz buluta gönderilmemiş yerel değişiklikleri koru
            let pending = Set(pushTasks.keys)
            var local: [String: Asset] = [:]
            for a in assets { local[a.id] = a }
            var merged: [Asset] = all.map { a in
                pending.contains(a.id) ? (local[a.id] ?? a) : a
            }
            let cloudIDs = Set(all.map { $0.id })
            for a in assets where pending.contains(a.id) && !cloudIDs.contains(a.id) {
                merged.append(a)
            }
            assets = merged
            syncError = nil
        } catch {
            if isCancel(error) { return }
            let m = error.localizedDescription
            if m.contains("INVALID_REFRESH_TOKEN") || m.contains("TOKEN_EXPIRED") || m.contains("USER_NOT_FOUND") {
                session = nil
            } else {
                syncError = L("Buluta bağlanılamadı: \(m)", "Could not connect to the cloud: \(m)")
            }
        }
    }

    private func push(_ a: Asset) async {
        guard signedIn else { return }
        do {
            let t = try await token()
            let body = try JSONSerialization.data(withJSONObject: ["fields": fields(a)])
            _ = try await send(docURL(a.id), method: "PATCH", body: body, contentType: "application/json", token: t)
            syncError = nil
        } catch {
            if isCancel(error) { return }
            syncError = L("Buluta kaydedilemedi: \(error.localizedDescription)", "Could not save to the cloud: \(error.localizedDescription)")
        }
    }

    private func deleteRemote(_ id: String) async {
        guard signedIn else { return }
        do {
            let t = try await token()
            _ = try await send(docURL(id), method: "DELETE", body: nil, contentType: nil, token: t)
            syncError = nil
        } catch {
            if isCancel(error) { return }
            syncError = L("Buluttan silinemedi: \(error.localizedDescription)", "Could not delete from the cloud: \(error.localizedDescription)")
        }
    }

    private func schedule(_ a: Asset, delay: Double) {
        pushTasks[a.id]?.cancel()
        let id = a.id
        pushTasks[id] = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if Task.isCancelled { return }
            guard let self else { return }
            let latest = self.assets.first(where: { $0.id == id }) ?? a
            await self.push(latest)
            if !Task.isCancelled { self.pushTasks[id] = nil }
        }
    }

    func upsert(_ a: Asset, delay: Double = 0) {
        if let i = assets.firstIndex(where: { $0.id == a.id }) {
            assets[i] = a
        } else {
            assets.append(a)
        }
        schedule(a, delay: delay)
    }

    func remove(_ id: String) {
        pushTasks[id]?.cancel()
        pushTasks[id] = nil
        assets.removeAll { $0.id == id }
        Task { await deleteRemote(id) }
    }

    func adjust(_ id: String, by d: Double) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        var a = assets[i]
        let old: Double = a.amount
        let new: Double = max(0, old + d)
        if a.cost > 0 && old > 0 {
            let avg: Double = a.cost / old
            if new > old {
                a.cost = avg * old + unitTL(a) * (new - old)
            } else {
                a.cost = avg * new
            }
        }
        a.amount = new
        upsert(a, delay: 0.5)
    }

    // MARK: Geçmiş (günlük net varlık, TL; web ile ortak)

    private var historyBase: String {
        let uid = session?.uid ?? "none"
        return "https://firestore.googleapis.com/v1/projects/\(Config.projectId)/databases/(default)/documents/users/\(uid)/history"
    }

    func snapHistory() async {
        guard signedIn, let r = rates, !assets.isEmpty else { return }
        let net = (usdSum(assets) * r.tryPerUSD).rounded()
        let debt = (-usdSum(assets.filter { $0.kind == .debt }) * r.tryPerUSD).rounded()
        let key = dayFmt.string(from: Date())
        if history[key] == net { return }
        history[key] = net
        do {
            let t = try await token()
            let f: [String: Any] = [
                "date": ["stringValue": key],
                "net": ["integerValue": String(Int(net))],
                "debt": ["integerValue": String(Int(debt))]
            ]
            let body = try JSONSerialization.data(withJSONObject: ["fields": f])
            guard let url = URL(string: historyBase + "/" + key) else { return }
            _ = try await send(url, method: "PATCH", body: body, contentType: "application/json", token: t)
        } catch {
            // geçmiş yazılamazsa yalnızca bu cihazda tutulur
        }
    }

    func pullHistory() async {
        guard signedIn else { return }
        do {
            let t = try await token()
            guard let url = URL(string: historyBase + "?pageSize=400") else { return }
            let data = try await send(url, method: "GET", body: nil, contentType: nil, token: t)
            let o = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            var merged = history
            for d in (o["documents"] as? [[String: Any]]) ?? [] {
                guard let name = d["name"] as? String,
                      let f = d["fields"] as? [String: Any],
                      let m = f["net"] as? [String: Any] else { continue }
                let key = String(name.split(separator: "/").last ?? "")
                if let dv = m["doubleValue"] as? Double { merged[key] = dv }
                else if let iv = m["integerValue"] as? String, let x = Double(iv) { merged[key] = x }
            }
            history = merged
        } catch {
            // izin yoksa yerel geçmiş kullanılır
        }
    }

    func tlToCur(_ tl: Double) -> Double {
        guard let r = rates else { return tl }
        return convert(usd: tl / r.tryPerUSD, to: cur)
    }

    func historyPoints() -> [HistPoint] {
        let keys = history.keys.sorted().suffix(120)
        var out: [HistPoint] = []
        for k in keys {
            guard let d = dayFmt.date(from: k), let v = history[k] else { continue }
            out.append(HistPoint(date: d, value: tlToCur(v)))
        }
        return out
    }

    // MARK: Vadeli hesap

    func depositNote(_ a: Asset) -> String? {
        guard a.kind == .deposit, depositTermDays(a) > 0 else { return nil }
        let u = unitUSD(Kind.fromCur(a.cur))
        let grow: Double = 1 + a.rate / 100 * depositTermDays(a) / 365.0
        let m: String = money(a.amount * grow * u)
        return L("vadede \(m)", "at maturity \(m)")
    }

    func gainUSD(_ a: Asset) -> Double? {
        if a.kind == .deposit { return usd(a) - a.amount * unitUSD(Kind.fromCur(a.cur)) }
        return plUSD(a)
    }

    // MARK: Dışa aktarma

    private func unitText(_ a: Asset) -> String {
        if !a.kind.unit.isEmpty { return a.kind.unitLabel }
        switch a.kind {
        case .tl, .usd, .eur, .gbp: return a.kind.rawValue
        default: return a.cur.uppercased()
        }
    }

    private func sortedForExport() -> [Asset] {
        assets.sorted { (l: Asset, r: Asset) -> Bool in
            if l.location != r.location { return l.location < r.location }
            if l.owner != r.owner { return l.owner < r.owner }
            return l.order < r.order
        }
    }

    func csvText() -> String {
        let rate = rates?.tryPerUSD ?? 0
        var lines: [String] = [L("Konum;Kişi;Grup;Ad;Miktar;Birim;Değer (TL);Maliyet (TL);Kâr/Zarar (TL)", "Location;Person;Group;Name;Amount;Unit;Value (TRY);Cost (TRY);Gain/Loss (TRY)")]
        for a in sortedForExport() {
            let tl = usd(a) * rate
            var gain = ""
            if let g = gainUSD(a) { gain = csvNum(g * rate) }
            var costCell: String = ""
            if a.cost > 0 { costCell = csvNum(a.cost) }
            var cells: [String] = [a.location, a.owner, a.kind.group.label, a.displayName]
            cells.append(csvNum(a.amount))
            cells.append(unitText(a))
            cells.append(csvNum(tl))
            cells.append(costCell)
            cells.append(gain)
            let escaped: [String] = cells.map { csvEsc($0) }
            lines.append(escaped.joined(separator: ";"))
        }
        let net = usdSum(assets) * rate
        let debt = -usdSum(assets.filter { $0.kind == .debt }) * rate
        lines.append("")
        let totalStr: String = csvNum(net + debt)
        let debtStr: String = csvNum(debt)
        let netStr: String = csvNum(net)
        lines.append(L(";;;Toplam varlık;;;\(totalStr)", ";;;Total assets;;;\(totalStr)"))
        lines.append(L(";;;Borç;;;\(debtStr)", ";;;Debt;;;\(debtStr)"))
        lines.append(L(";;;Net varlık;;;\(netStr)", ";;;Net worth;;;\(netStr)"))
        let body: String = lines.joined(separator: "\r\n")
        return "\u{FEFF}\(body)"
    }

    func reportLines() -> [String] {
        let rate = rates?.tryPerUSD ?? 0
        let today: String = trDay(dayFmt.string(from: Date()))
        var lines: [String] = [L("Varlık raporu · \(today)", "Asset report · \(today)"), ""]
        for a in sortedForExport() {
            let tl = (usd(a) * rate).formatted(.number.precision(.fractionLength(0)))
            let amt: String = amountText(a)
            let line: String = "\(a.location) · \(a.owner) · \(a.displayName) · \(amt) · ₺\(tl)"
            lines.append(line)
        }
        lines.append("")
        for g in AssetGroup.allCases {
            let items = assets.filter { $0.kind.group == g }
            if items.isEmpty { continue }
            let v = (usdSum(items) * rate).formatted(.number.precision(.fractionLength(0)))
            lines.append("\(g.label): ₺\(v)")
        }
        let net = (usdSum(assets) * rate).formatted(.number.precision(.fractionLength(0)))
        lines.append(L("Net varlık: ₺\(net)", "Net worth: ₺\(net)"))
        return lines
    }

    func csvURL() -> URL? {
        let day: String = dayFmt.string(from: Date())
        let url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("varliklar-\(day).csv")
        do {
            try csvText().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func pdfURL() -> URL? {
        let lines = reportLines()
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 40
            for line in lines {
                if y > 800 {
                    ctx.beginPage()
                    y = 40
                }
                let text: String = String(line.prefix(105))
                (text as NSString).draw(at: CGPoint(x: 36, y: y), withAttributes: attrs)
                y += 15
            }
        }
        let day: String = dayFmt.string(from: Date())
        let url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("varliklar-\(day).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Hesaplar

    /// 1 birimin dolar karşılığı
    func unitUSD(_ k: Kind) -> Double {
        guard let r = rates else { return k == .usd ? 1 : 0 }
        switch k {
        case .usd: return 1
        case .tl: return 1 / r.tryPerUSD
        case .eur: return 1 / r.eurPerUSD
        case .gbp: return 1 / r.gbpPerUSD
        case .custom, .stock, .crypto, .fund, .deposit, .debt: return 0
        default: return (k.goldGrams ?? 0) * r.goldUSDPerGram
        }
    }

    func usd(_ a: Asset) -> Double {
        let u: Double = unitUSD(Kind.fromCur(a.cur))
        switch a.kind {
        case .custom:
            return a.amount * u
        case .stock, .crypto, .fund:
            return a.amount * a.price * u
        case .debt:
            return -a.amount * u
        case .deposit:
            let grow: Double = 1 + a.rate / 100 * depositDays(a) / 365
            return a.amount * grow * u
        default:
            return a.amount * unitUSD(a.kind)
        }
    }

    func usdSum(_ items: [Asset]) -> Double { items.reduce(0) { $0 + usd($1) } }

    func convert(usd: Double, to c: Kind) -> Double {
        guard let r = rates else { return usd }
        switch c {
        case .tl: return usd * r.tryPerUSD
        case .eur: return usd * r.eurPerUSD
        case .gbp: return usd * r.gbpPerUSD
        default: return usd
        }
    }

    /// Dolar değerini seçili para biriminde yazar; gizliyse nokta gösterir.
    func money(_ usd: Double) -> String {
        moneyCur(convert(usd: usd, to: cur))
    }

    /// Zaten seçili para biriminde olan değeri yazar
    func moneyCur(_ v: Double) -> String {
        if hidden { return "••••••" }
        let sym = ["TL": "₺", "USD": "$", "EUR": "€", "GBP": "£"][cur.rawValue] ?? ""
        let sign: String = v < -0.5 ? "−" : ""
        let n: String = abs(v).formatted(.number.precision(.fractionLength(0)))
        return sign + sym + n
    }

    func tlPrice(_ k: Kind) -> String {
        guard let r = rates else { return "—" }
        let v = unitUSD(k) * r.tryPerUSD
        let digits: Int = k.goldGrams == nil ? 2 : 0
        let n: String = v.formatted(.number.precision(.fractionLength(digits)))
        return "₺\(n)"
    }

    func buckets(sortByValue: Bool, key: (Asset) -> String) -> [Bucket] {
        let list = Dictionary(grouping: assets, by: key)
            .map { entry in
                Bucket(name: entry.key.isEmpty ? "—" : entry.key,
                       items: entry.value.sorted { l, r in (l.order, l.id) < (r.order, r.id) })
            }
        return sortByValue ? list.sorted { usdSum($0.items) > usdSum($1.items) }
                           : list.sorted { $0.name < $1.name }
    }
}

func pctSuffix(_ p: Double?) -> String {
    guard let p, p.isFinite else { return "" }
    let n: String = abs(p).formatted(.number.precision(.fractionLength(1)))
    return " (%\(n))"
}

func arrowText(_ v: Double, _ s: String) -> String {
    let mark: String = v >= 0 ? "▲" : "▼"
    return "\(mark) \(s)"
}

func amountText(_ a: Asset) -> String {
    let n = a.amount.formatted(.number.precision(.fractionLength(0...2)))
    if a.kind == .custom || a.kind == .debt || a.kind == .deposit { return "\(n) \(a.cur.uppercased())" }
    if a.kind.unit.isEmpty { return n }
    return "\(n) \(a.kind.unitLabel)"
}

// MARK: - Ana yapı

// MARK: - Borç hatırlatıcıları

enum Reminders {
    /// Son günü olan her borç için, son günden 1 gün önce sabah 09:00'da bildirim kurar.
    static func sync(_ assets: [Asset]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old: [String] = pending.map { $0.identifier }.filter { $0.hasPrefix("debt-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        let debts: [Asset] = assets.filter { $0.kind == .debt && parseDay($0.maturity) != nil }
        if debts.isEmpty { return }
        let granted: Bool = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if !granted { return }
        let cal = Calendar.current
        for a in debts {
            guard let due = parseDay(a.maturity),
                  let day = cal.date(byAdding: .day, value: -1, to: due),
                  let fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                  fire > Date() else { continue }
            let name: String = a.typeName.isEmpty ? L("Borç", "Debt") : a.typeName
            let content = UNMutableNotificationContent()
            content.title = L("Borç son günü yarın", "Debt due tomorrow")
            content.body = L("\(name) için son gün yarın (\(trDay(a.maturity))).", "\(name) is due tomorrow (\(trDay(a.maturity))).")
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "debt-\(a.id)", content: content, trigger: trigger)
            try? await center.add(req)
        }
    }
}

// MARK: - Kilit (Face ID / parola)

@MainActor
final class AppLock: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "lockOn") }
    }
    @Published var locked: Bool
    private var busy = false

    init() {
        let on: Bool = UserDefaults.standard.bool(forKey: "lockOn")
        enabled = on
        locked = on
    }

    func lockNow() {
        if enabled { locked = true }
    }

    private func authenticate() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        if !ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) { return false }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                localizedReason: L("Varlıklarını görmek için kimliğini doğrula", "Authenticate to view your assets"))
        } catch {
            return false
        }
    }

    func unlock() async {
        if !locked || busy { return }
        busy = true
        let ok: Bool = await authenticate()
        busy = false
        if ok { locked = false }
    }

    /// Ayarlardan açma / kapatma: önce kimlik doğrulanır
    func setEnabled(_ on: Bool) async {
        if busy { return }
        busy = true
        let ok: Bool = await authenticate()
        busy = false
        if ok { enabled = on }
    }
}

struct CoverView: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.muted)
                Text(L("Varlıklarım", "My Assets")).font(.title2.bold())
                if lock.locked {
                    Button(L("Kilidi aç", "Unlock")) { Task { await lock.unlock() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct LangCard: View {
    @AppStorage("lang") private var lang: String = "auto"

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Dil", "Language")).font(.headline)
                Picker(L("Dil", "Language"), selection: $lang) {
                    Text("Auto").tag("auto")
                    Text("Türkçe").tag("tr")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct LockCard: View {
    @ObservedObject var lock: AppLock
    @ObservedObject var store: Store

    private var binding: Binding<Bool> {
        Binding<Bool>(get: { lock.enabled }, set: { v in Task { await lock.setEnabled(v) } })
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Gizlilik", "Privacy")).font(.headline)
                Toggle(L("Face ID ile kilitle", "Lock with Face ID"), isOn: binding)
                Toggle(L("Net varlık açılışta gizli", "Hide net worth on launch"), isOn: $store.netHideLaunch)
                Text(L("Açıkken uygulamaya her dönüşte Face ID (veya cihaz parolası) istenir. Uygulama değiştiricide içerik gizlenir.", "When on, Face ID (or the device passcode) is required every time you return to the app. Content is hidden in the app switcher."))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var store = Store()
    @StateObject private var lock = AppLock()
    @AppStorage("lang") private var lang: String = "auto"
    @State private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    private var tabs: [(Int, String, String)] {
        [
            (0, L("Özet", "Summary"), "chart.pie.fill"),
            (1, L("Varlıklar", "Assets"), "list.bullet"),
            (2, L("Kurlar", "Rates"), "turkishlirasign"),
            (3, L("Ayarlar", "Settings"), "gearshape.fill")
        ]
    }

    var body: some View {
        Group {
            if store.signedIn {
                mainView
            } else {
                LoginView(store: store)
            }
        }
        .id(lang)
        .task { await store.reloadAll() }
        .task { await lock.unlock() }
        .onChange(of: scenePhase) { phase in
            handlePhase(phase)
        }
        .onChange(of: store.signedIn) { _ in
            tab = 0
        }
        .overlay { cover }
    }

    private func handlePhase(_ phase: ScenePhase) {
        if phase == .background { lock.lockNow() }
        if phase == .active {
            Task { await store.reloadAll() }
            Task { await lock.unlock() }
        }
    }

    @ViewBuilder private var cover: some View {
        if lock.locked || scenePhase != .active {
            CoverView(lock: lock)
        }
    }

    private var mainView: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                switch tab {
                case 0: SummaryView(store: store)
                case 1: AssetsView(store: store)
                case 2: RatesView(store: store)
                default: SettingsView(store: store, lock: lock)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
    }

    private var tabBar: some View {
        HStack {
            ForEach(tabs, id: \.0) { t in
                Button { tab = t.0 } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.2).font(.system(size: 20))
                        Text(t.1).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .foregroundStyle(tab == t.0 ? Theme.pri : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - Giriş

struct LoginView: View {
    @ObservedObject var store: Store
    @State private var user = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var signup = false
    @State private var busy = false
    @State private var err: String?

    func friendly(_ m: String) -> String {
        if m.contains("EMAIL_EXISTS") { return L("Bu kullanıcı adı alınmış", "This username is already taken") }
        if m.contains("WEAK_PASSWORD") { return L("Şifre en az 6 karakter olmalı", "Password must be at least 6 characters") }
        if m.contains("OPERATION_NOT_ALLOWED") { return L("Hesap oluşturma kapalı", "Account creation is disabled") }
        if m.contains("TOO_MANY") { return L("Çok fazla deneme, biraz bekle", "Too many attempts, please wait a bit") }
        if m.contains("INVALID") || m.contains("EMAIL") || m.contains("PASSWORD") { return L("Kullanıcı adı veya şifre hatalı", "Wrong username or password") }
        return L("İşlem yapılamadı: ", "Operation failed: ") + m
    }

    func validName(_ n: String) -> Bool {
        let t = n.trimmingCharacters(in: .whitespaces)
        if t.count < 3 || t.count > 24 { return false }
        return t.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }
    }

    func submit() async {
        busy = true
        err = nil
        do {
            if signup {
                if !validName(user) { err = L("Kullanıcı adı 3-24 karakter; harf, rakam, nokta, alt çizgi", "Username must be 3–24 characters: letters, digits, dot, underscore"); busy = false; return }
                if password.count < 6 { err = L("Şifre en az 6 karakter olmalı", "Password must be at least 6 characters"); busy = false; return }
                if password != password2 { err = L("İki şifre aynı değil", "Passwords do not match"); busy = false; return }
                try await store.signUp(user: user, password: password)
            } else {
                try await store.signIn(user: user, password: password)
            }
        } catch {
            err = friendly(error.localizedDescription)
        }
        busy = false
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("Varlıklarımız", "Our Assets")).font(.largeTitle.bold())
                Text(signup ? L("Yeni hesap oluştur", "Create new account") : L("Devam etmek için giriş yap", "Sign in to continue"))
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 8)

                TextField(signup ? L("Kullanıcı adı", "Username") : L("Kullanıcı adı veya e-posta", "Username or email"), text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                SecureField(L("Şifre", "Password"), text: $password)
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                if signup {
                    SecureField(L("Şifre (tekrar)", "Password (again)"), text: $password2)
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }

                if let err {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if busy { ProgressView().tint(.white) } else { Text(signup ? L("Hesap oluştur", "Create account") : L("Giriş yap", "Sign in")).fontWeight(.bold) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .foregroundStyle(.white)
                    .background(Theme.pri, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(busy || user.isEmpty || password.isEmpty)

                Button(signup ? L("Zaten hesabım var", "I already have an account") : L("Yeni hesap oluştur", "Create new account")) {
                    signup.toggle()
                    err = nil
                }
                .font(.subheadline)
            }
            .padding(24)
            .frame(maxWidth: 420)
        }
    }
}

// MARK: - Ayarlar

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var lock: AppLock
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text(L("Ayarlar", "Settings")).font(.largeTitle.bold())
                    Spacer()
                }
                .padding(.top, 8)

                if let s = store.session {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("Hesap", "Account")).font(.headline)
                            Text(L("Giriş yapılan hesap: \(store.shownName(s.email))", "Signed in as: \(store.shownName(s.email))"))
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                            Button(L("Çıkış yap", "Sign out"), role: .destructive) { store.signOut() }
                            Button(L("Hesabı ve verilerimi sil", "Delete account and my data"), role: .destructive) { confirmDelete = true }
                        }
                    }
                }

                LangCard()

                LockCard(lock: lock, store: store)

                AlertsCard(store: store)

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Dışa aktar", "Export")).font(.headline)
                        Text(L("Excel dosyası noktalı virgülle ayrılmış CSV olarak paylaşılır; Excel'de doğrudan açılır.", "Shared as a semicolon-separated CSV file; opens directly in Excel."))
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                        if let csv = store.csvURL() {
                            ShareLink(item: csv) { Label(L("Excel (CSV)", "Excel (CSV)"), systemImage: "tablecells") }
                        }
                        if let pdf = store.pdfURL() {
                            ShareLink(item: pdf) { Label(L("PDF raporu", "PDF report"), systemImage: "doc.richtext") }
                        }
                    }
                }

                if let e = store.syncError {
                    Text(e)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.48, green: 0.35, blue: 0))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 1, green: 0.96, blue: 0.84), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .alert(L("Hesabın ve bütün kayıtların kalıcı olarak silinecek. Emin misin?", "Your account and all records will be permanently deleted. Are you sure?"), isPresented: $confirmDelete) {
            Button(L("Sil", "Delete"), role: .destructive) { Task { await store.deleteAccount() } }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        }
    }
}

// MARK: - Özet

enum SumMode: String, CaseIterable, Identifiable {
    case group = "Türe göre", loc = "Konuma göre", owner = "Kişiye göre"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .group: return L("Türe göre", "By type")
        case .loc: return L("Konuma göre", "By location")
        case .owner: return L("Kişiye göre", "By person")
        }
    }
}

struct ReloadButton: View {
    @ObservedObject var store: Store

    var body: some View {
        Button {
            Task { await store.reloadAll() }
        } label: {
            icon
                .font(.title3)
                .frame(width: 24, height: 24)
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var icon: some View {
        if store.loading {
            ProgressView()
        } else {
            Image(systemName: "arrow.clockwise")
        }
    }
}

struct EyeButton: View {
    @ObservedObject var store: Store

    private var iconName: String {
        store.hidden ? "eye.slash.fill" : "eye.fill"
    }

    var body: some View {
        Button {
            store.hidden.toggle()
        } label: {
            Image(systemName: iconName)
                .font(.title3)
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SummaryView: View {
    @ObservedObject var store: Store
    @State private var mode: SumMode = .group

    var total: Double { store.usdSum(store.assets) }
    var debtUSD: Double { -store.usdSum(store.assets.filter { $0.kind == .debt }) }
    var gross: Double { total + debtUSD }

    var groupsShown: [AssetGroup] {
        AssetGroup.allCases.filter { g in
            g.alwaysShown || store.assets.contains { $0.kind.group == g }
        }
    }

    var slices: [Slice] {
        switch mode {
        case .group:
            return AssetGroup.allCases
                .map { g in Slice(name: g.label,
                                  value: store.usdSum(store.assets.filter { $0.kind.group == g }),
                                  color: g.color) }
                .filter { $0.value > 0 }
        case .loc, .owner:
            let b = store.buckets(sortByValue: true) { mode == .loc ? $0.location : $0.owner }
            var out: [Slice] = []
            for (i, x) in b.enumerated() {
                let v: Double = store.usdSum(x.items.filter { $0.kind != .debt })
                if v > 0 { out.append(Slice(name: x.name, value: v, color: palette[i % palette.count])) }
            }
            return out
        }
    }

    private var netMasked: Bool { store.hidden || store.netHidden }

    private var netText: String {
        netMasked ? "••••••" : store.money(total)
    }

    private var debtLine: String {
        if netMasked { return "••••••" }
        let g: String = store.money(gross)
        let d: String = store.money(debtUSD)
        return L("Varlık \(g) · Borç \(d)", "Assets \(g) · Debt \(d)")
    }

    private var totalTitle: String {
        debtUSD > 0 ? L("Net varlık", "Net worth") : L("Toplam varlık", "Total assets")
    }

    private var totalHeader: some View {
        HStack {
            Text(totalTitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button {
                store.netHidden.toggle()
            } label: {
                Image(systemName: store.netHidden ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            totalHeader
            Text(netText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
            if debtUSD > 0 {
                Text(debtLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            if let e = store.syncError {
                Text(e).font(.caption).foregroundStyle(.yellow)
            } else if let e = store.error {
                Text(e).font(.caption).foregroundStyle(.yellow)
            } else if let r = store.rates {
                Text(L("Kurlar: \(r.updated.formatted(date: .abbreviated, time: .shortened))", "Rates: \(r.updated.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.29, green: 0.25, blue: 0.82),
                                    Color(red: 0.18, green: 0.48, blue: 0.88)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    var groupCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
            ForEach(groupsShown) { g in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(g.color).frame(width: 10, height: 10)
                        Text(g.label).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Text(store.money(store.usdSum(store.assets.filter { $0.kind.group == g })))
                        .font(.headline)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    @ViewBuilder
    func historyCard(_ pts: [HistPoint]) -> some View {
        let first: Double = pts.first?.value ?? 0
        let last: Double = pts.last?.value ?? 0
        let change: Double = last - first
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Net varlık geçmişi", "Net worth history")).font(.headline)
                    Spacer()
                    if pts.count > 1 {
                        Text(arrowText(change, store.moneyCur(abs(change))))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(change >= 0 ? Color.green : Color.red)
                    }
                }
                if pts.count < 2 {
                    Text(L("Grafik, uygulamayı açtığın her gün bir nokta ekler. En az 2 gün gerekir.", "The chart adds one point for each day you open the app. At least 2 days are needed."))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                } else {
                    Chart(pts) { p in
                        AreaMark(x: .value("Gün", p.date), y: .value("Değer", p.value))
                            .foregroundStyle(Theme.pri.opacity(0.15))
                        LineMark(x: .value("Gün", p.date), y: .value("Değer", p.value))
                            .foregroundStyle(Theme.pri)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis(.hidden)
                    .frame(height: 140)
                }
            }
        }
    }

    private var curSeg: some View {
        Seg(items: [Kind.tl, .usd, .eur, .gbp], title: { $0.rawValue },
            sel: Binding(get: { store.cur }, set: { store.curRaw = $0.rawValue }))
    }

    @ViewBuilder private var headerRow: some View {
        HStack {
            Text(L("Varlıklarımız", "Our Assets")).font(.largeTitle.bold())
            Spacer()
            EyeButton(store: store)
            ReloadButton(store: store)
        }
        .padding(.top, 8)
    }

    private func plRow(_ title: String, _ pl: Double, _ cost: Double) -> some View {
        let pct: Double? = cost > 0 ? pl / cost * 100 : nil
        let txt: String = store.hidden ? "••••" : arrowText(pl, store.money(abs(pl))) + pctSuffix(pct)
        return HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            Text(txt)
                .font(.headline)
                .foregroundStyle(pl >= 0 ? Color.green : Color.red)
        }
        .font(.subheadline)
    }

    @ViewBuilder private var plCard: some View {
        if let pl = store.totalPLUSD() {
            Card {
                VStack(spacing: 8) {
                    plRow(L("Toplam kâr / zarar", "Total gain / loss"), pl, store.totalCostUSD())
                    if let g = store.goldPL(), abs(g.cost - store.totalCostUSD()) > 0.01 {
                        plRow(L("Altın kâr / zarar", "Gold gain / loss"), g.pl, g.cost)
                    }
                }
            }
        }
    }

    @ViewBuilder private var goldCard: some View {
        let gold = store.goldLines()
        if !gold.isEmpty {
            Card {
                VStack(spacing: 10) {
                    HStack {
                        Text(L("Altın varlığımız", "Our gold")).font(.headline)
                        Spacer()
                        Text(store.money(gold.reduce(0) { $0 + $1.usd }))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(gold) { g in
                        HStack {
                            Circle().fill(AssetGroup.gold.color).frame(width: 8, height: 8)
                            Text(g.kind.title)
                            Spacer()
                            Text(goldQtyText(g, hidden: store.hidden))
                                .fontWeight(.semibold)
                            Text(store.money(g.usd))
                                .foregroundStyle(Theme.muted)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private func pctText(_ v: Double) -> String {
        if store.hidden || gross <= 0 { return "" }
        let n: Int = Int((v / gross * 100).rounded())
        return "%" + String(n)
    }

    @ViewBuilder private var distCard: some View {
        Card {
            VStack(spacing: 14) {
                Seg(items: SumMode.allCases, title: { $0.label }, sel: $mode, bg: Theme.bg)

                if slices.isEmpty {
                    Text(L("Henüz varlık yok.\nVarlıklar sekmesinden ekleyebilirsin.", "No assets yet.\nYou can add them from the Assets tab."))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                } else {
                    Chart(slices) { s in
                        SectorMark(angle: .value("Değer", s.value),
                                   innerRadius: .ratio(0.62),
                                   angularInset: 1.5)
                            .foregroundStyle(s.color)
                            .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 220)

                    VStack(spacing: 10) {
                        ForEach(slices) { s in
                            HStack {
                                Circle().fill(s.color).frame(width: 10, height: 10)
                                Text(s.name)
                                Spacer()
                                Text(store.money(s.value))
                                Text(pctText(s.value))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerRow
                curSeg
                totalCard
                groupCards
                plCard
                goldCard
                if !store.hidden { historyCard(store.historyPoints()) }
                distCard
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await store.reloadAll() }
    }
}

// MARK: - Varlıklar

enum ListMode: String, CaseIterable, Identifiable {
    case loc = "Konuma göre", owner = "Kişiye göre"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .loc: return L("Konuma göre", "By location")
        case .owner: return L("Kişiye göre", "By person")
        }
    }
}

struct AssetsView: View {
    @ObservedObject var store: Store
    @State private var mode: ListMode = .loc
    @State private var editing: Asset?
    @State private var adding: AddRequest?

    var locations: [String] { Array(Set(store.assets.map(\.location))).filter { !$0.isEmpty }.sorted() }
    var owners: [String] { Array(Set(store.assets.map(\.owner))).filter { !$0.isEmpty }.sorted() }
    var customTypes: [String] {
        Array(Set(store.assets.filter { $0.kind == .custom && !$0.typeName.isEmpty }.map(\.typeName))).sorted()
    }

    func request(for name: String) -> AddRequest {
        let n = name == "—" ? "" : name
        return mode == .loc ? AddRequest(location: n, owner: "") : AddRequest(location: "", owner: n)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 8) {
                    HStack {
                        Text(L("Varlıklar", "Assets")).font(.largeTitle.bold())
                        Spacer()
                    }
                    .padding(.top, 8)

                    Seg(items: ListMode.allCases, title: { $0.label }, sel: $mode)
                        .padding(.bottom, 6)

                    if store.assets.isEmpty {
                        Text(L("Henüz varlık yok.\nSağ alttaki + ile ekle.", "No assets yet.\nAdd one with the + at the bottom right."))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.muted)
                            .padding(.vertical, 40)
                    }

                    ForEach(store.buckets(sortByValue: false) { mode == .loc ? $0.location : $0.owner }) { b in
                        HStack {
                            Text(b.name).font(.headline)
                            Button { adding = request(for: b.name) } label: {
                                Image(systemName: "plus")
                                    .font(.caption.weight(.bold))
                                    .frame(width: 24, height: 24)
                                    .background(Theme.line, in: Circle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Text(store.money(store.usdSum(b.items)))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 10)

                        VStack(spacing: 0) {
                            ForEach(Array(b.items.enumerated()), id: \.element.id) { i, a in
                                if i > 0 { Divider() }
                                row(a, in: b.items)
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 90)
            }
            .refreshable { await store.reloadAll() }

            Button { adding = AddRequest() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Theme.pri, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $adding) { req in
            EditView(store: store,
                     asset: Asset(location: req.location, owner: req.owner, kind: .tl, amount: 0),
                     locations: locations, owners: owners, customTypes: customTypes, isNew: true,
                     onSave: { store.upsert($0) },
                     onSaveAndNew: { a in
                         store.upsert(a)
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                             adding = AddRequest(location: a.location, owner: a.owner)
                         }
                     },
                     onDelete: nil)
        }
        .sheet(item: $editing) { a in
            EditView(store: store,
                     asset: a, locations: locations, owners: owners, customTypes: customTypes, isNew: false,
                     onSave: { store.upsert($0) },
                     onSaveAndNew: nil,
                     onDelete: { store.remove(a.id) })
        }
    }

    @ViewBuilder
    func row(_ a: Asset, in bucketItems: [Asset]) -> some View {
        let quick = !a.kind.unit.isEmpty
        let base = mode == .loc ? a.owner : a.location
        let sub: String = rowSubtitle(a, base: base)
        HStack(spacing: 8) {
            Button { editing = a } label: {
                HStack(spacing: 10) {
                    Circle().fill(a.kind.group.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.displayName).font(.body.weight(.semibold))
                        Text(sub).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if quick {
                Button { store.adjust(a.id, by: -1) } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Theme.line, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Button { editing = a } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(store.hidden ? "••••" : amountText(a)).font(.body.weight(.semibold))
                    Text(store.money(store.usd(a))).font(.caption).foregroundStyle(Theme.muted)
                    if let note = store.depositNote(a) {
                        Text(note).font(.caption2).foregroundStyle(Theme.muted)
                    }
                    if !store.hidden, let pl = store.gainUSD(a) {
                        Text(arrowText(pl, store.money(abs(pl))) + pctSuffix(store.plPct(a)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(pl >= 0 ? Color.green : Color.red)
                    }
                }
                .frame(minWidth: 64, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if quick {
                Button { store.adjust(a.id, by: 1) } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Theme.line, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        // Basılı tutup sürükleyerek aynı grup içinde yer değiştir
        .draggable(a.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let dragged = ids.first else { return false }
            store.moveAsset(dragged, onto: a.id, in: bucketItems)
            return true
        }
    }
}

// MARK: - Kurlar

struct RatesView: View {
    @ObservedObject var store: Store

    private func onsText(_ r: Rates) -> String {
        let n: String = (r.goldUSDPerGram * 31.1035).formatted(.number.precision(.fractionLength(0)))
        return "$\(n)"
    }

    private let kinds: [Kind] = [.usd, .eur, .gbp, .gold, .yarimGram, .ceyrek, .yarim, .tam, .cumhuriyet]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text(L("Kurlar", "Rates")).font(.largeTitle.bold())
                    Spacer()
                    ReloadButton(store: store)
                }
                .padding(.top, 8)

                if let e = store.syncError ?? store.error ?? store.stockError {
                    Text(e)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.48, green: 0.35, blue: 0))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 1, green: 0.96, blue: 0.84), in: RoundedRectangle(cornerRadius: 12))
                }

                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(kinds.enumerated()), id: \.element.id) { i, k in
                            if i > 0 { Divider() }
                            HStack {
                                Circle().fill(k.group.color).frame(width: 10, height: 10)
                                Text(k == .gold ? L("Gram altın", "Gold gram") : k.title)
                                Spacer()
                                Text(store.tlPrice(k)).font(.body.weight(.semibold))
                            }
                            .padding(.vertical, 11)
                        }
                        if let r = store.rates {
                            Divider()
                            HStack {
                                Text(L("Ons altın", "Gold ounce"))
                                Spacer()
                                Text(onsText(r))
                                    .font(.body.weight(.semibold))
                            }
                            .padding(.vertical, 11)
                        }
                    }
                }

                // Sahip olunan hisseler
                let held = store.heldStocks
                if !held.isEmpty {
                    Card {
                        VStack(spacing: 0) {
                            HStack {
                                Text(L("Fiyatlı varlıklarım", "Priced assets")).font(.headline)
                                Spacer()
                            }
                            .padding(.bottom, 6)
                            ForEach(Array(held.enumerated()), id: \.element.id) { i, h in
                                if i > 0 { Divider() }
                                HStack {
                                    Circle().fill(h.group.color).frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(h.name).lineLimit(1)
                                        Text(heldSubtitle(h))
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text(priceText(h.price, h.cur))
                                        .font(.body.weight(.semibold))
                                }
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Altın değerleri ons fiyatından hesaplanan has altın karşılığıdır. Kuyumcu fiyatı işçilik farkıyla biraz farklı olabilir.", "Gold values are pure-gold equivalents calculated from the ounce price. Jeweler prices may differ slightly due to workmanship."))
                    if let r = store.rates {
                        Text(L("Son güncelleme: \(r.updated.formatted(date: .abbreviated, time: .shortened))", "Last update: \(r.updated.formatted(date: .abbreviated, time: .shortened))"))
                    }
                    if !held.isEmpty {
                        Text(L("Hisse fiyatları Yahoo Finance'ten (yaklaşık 15 dakika gecikmeli), kripto fiyatları CoinGecko'dan gelir.", "Stock prices come from Yahoo Finance (about 15 minutes delayed); crypto prices come from CoinGecko."))
                        if let t = store.stockUpdated {
                            Text(L("Hisse güncelleme: \(t.formatted(date: .abbreviated, time: .shortened))", "Stock update: \(t.formatted(date: .abbreviated, time: .shortened))"))
                        }
                    }
                    Link("Rates By Exchange Rate API", destination: URL(string: "https://www.exchangerate-api.com")!)
                    Text(L("Altın: gold-api.com", "Gold: gold-api.com"))
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await store.reloadAll() }
    }
}

// MARK: - Ekleme / düzenleme

struct EditView: View {
    let store: Store
    @State private var asset: Asset
    @State private var amountStr: String
    @State private var deltaStr = ""
    @State private var buyStr = ""
    @State private var priceStr: String
    @State private var costStr: String
    @State private var rateStr: String
    @State private var startDate: Date
    @State private var matDate: Date
    @State private var hasDue: Bool
    @State private var query = ""
    @State private var hits: [StockHit] = []
    @State private var searching = false
    @State private var note: String?
    let locations: [String]
    let owners: [String]
    let customTypes: [String]
    let isNew: Bool
    let onSave: (Asset) -> Void
    let onSaveAndNew: ((Asset) -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(store: Store, asset: Asset, locations: [String], owners: [String], customTypes: [String], isNew: Bool,
         onSave: @escaping (Asset) -> Void, onSaveAndNew: ((Asset) -> Void)?, onDelete: (() -> Void)?) {
        self.store = store
        _asset = State(initialValue: asset)
        _amountStr = State(initialValue: asset.amount == 0 ? "" : fmtIn(asset.amount))
        _priceStr = State(initialValue: asset.price == 0 ? "" : fmtIn(asset.price))
        _costStr = State(initialValue: (asset.cost == 0 || asset.amount <= 0) ? "" : fmtIn(asset.cost / asset.amount))
        _rateStr = State(initialValue: asset.rate == 0 ? "" : fmtIn(asset.rate))
        _startDate = State(initialValue: parseDay(asset.start) ?? Date())
        let defMat: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        _matDate = State(initialValue: parseDay(asset.maturity) ?? defMat)
        _hasDue = State(initialValue: asset.kind == .debt && parseDay(asset.maturity) != nil)
        self.locations = locations
        self.owners = owners
        self.customTypes = customTypes
        self.isNew = isNew
        self.onSave = onSave
        self.onSaveAndNew = onSaveAndNew
        self.onDelete = onDelete
    }

    var amountLabel: String {
        switch asset.kind {
        case .custom: return L("Toplam değer", "Total value")
        case .stock: return L("Adet (lot)", "Quantity (lots)")
        case .crypto: return L("Miktar", "Amount")
        case .fund: return L("Adet (pay)", "Quantity (shares)")
        case .debt: return L("Borç tutarı", "Debt amount")
        case .deposit: return L("Anapara", "Principal")
        default: break
        }
        switch asset.kind.unit {
        case "adet": return L("Adet", "Quantity")
        case "gr": return L("Gram", "Grams")
        default: return L("Tutar", "Amount")
        }
    }

    var showsCost: Bool {
        switch asset.kind {
        case .tl, .custom, .debt, .deposit: return false
        default: return true
        }
    }

    var searchable: Bool { asset.kind == .stock || asset.kind == .crypto }

    var nameLabel: String {
        switch asset.kind {
        case .debt: return L("Borcun adı (örn. Kredi kartı, konut kredisi)", "Debt name (e.g. credit card, mortgage)")
        case .deposit: return L("Hesap adı (isteğe bağlı)", "Account name (optional)")
        default: return L("Türün adı", "Type name")
        }
    }

    var namePlaceholder: String {
        switch asset.kind {
        case .debt: return L("Örn. Kredi kartı", "e.g. Credit card")
        case .deposit: return L("Örn. 3 aylık vadeli", "e.g. 3-month deposit")
        default: return L("Örn. Araç, Ev", "e.g. Car, House")
        }
    }

    var symbolLabel: String {
        switch asset.kind {
        case .crypto: return L("CoinGecko kimliği (aramayla dolar, örn. bitcoin)", "CoinGecko ID (filled in by search, e.g. bitcoin)")
        case .fund: return L("Fon kodu (isteğe bağlı, örn. TCD)", "Fund code (optional, e.g. TCD)")
        default: return L("Sembol (aramayla dolar, elle de yazılabilir. BIST için sonuna .IS, örn. THYAO.IS)", "Symbol (filled in by search, or type it. For BIST add .IS, e.g. THYAO.IS)")
        }
    }

    var searchLabel: String {
        asset.kind == .crypto ? L("Kripto ara (örn. bitcoin, eth)", "Search crypto (e.g. bitcoin, eth)") : L("Hisse ara (şirket adı veya sembol, örn. THY)", "Search stocks (company name or symbol, e.g. THY)")
    }

    var priceNote: String {
        asset.kind == .fund ? L("Fon fiyatı otomatik çekilmez; güncel birim fiyatı sen yaz.", "Fund price is not fetched automatically; enter the current unit price.") : L("Birim fiyat (uygulama açılınca otomatik güncellenir)", "Unit price (updates automatically when the app opens)")
    }

    var valid: Bool {
        let hasPlace = !asset.location.trimmingCharacters(in: .whitespaces).isEmpty
            && !asset.owner.trimmingCharacters(in: .whitespaces).isEmpty
        let customOK = asset.kind != .custom || !asset.typeName.trimmingCharacters(in: .whitespaces).isEmpty
        let needsSymbol = asset.kind == .stock || asset.kind == .crypto
        let stockOK = !needsSymbol || !asset.symbol.trimmingCharacters(in: .whitespaces).isEmpty
        return hasPlace && customOK && stockOK
    }

    private var deltaVal: Double { numTR(deltaStr) }

    private var buyPlaceholder: String {
        let u: Double = store.unitTL(asset)
        return u > 0 ? fmtIn((u * 100).rounded() / 100) : "0"
    }

    /// Ortalama alış fiyatından toplam maliyeti bulur; yeni alımda ağırlıklı ortalamayı günceller
    private func newCost(_ a: Asset) -> Double {
        let old: Double = max(0, numTR(amountStr))
        let d: Double = deltaVal
        var avg: Double = max(0, numTR(costStr))
        if d > 0 {
            var bp: Double = max(0, numTR(buyStr))
            if bp <= 0 && avg > 0 { bp = store.unitTL(a) }
            if bp > 0 {
                if avg > 0 && old > 0 {
                    avg = (avg * old + bp * d) / (old + d)
                } else if avg <= 0 {
                    avg = old > 0 ? 0 : bp
                }
            }
        }
        return avg * a.amount
    }

    func built() -> Asset {
        var a = asset
        a.amount = max(0, numTR(amountStr) + numTR(deltaStr))
        a.location = a.location.trimmingCharacters(in: .whitespaces)
        a.owner = a.owner.trimmingCharacters(in: .whitespaces)
        a.rate = 0
        a.start = ""
        a.maturity = ""
        switch a.kind {
        case .custom:
            a.typeName = a.typeName.trimmingCharacters(in: .whitespaces)
            a.symbol = ""
            a.price = 0
        case .debt, .deposit:
            a.typeName = a.typeName.trimmingCharacters(in: .whitespaces)
            a.symbol = ""
            a.price = 0
            if a.kind == .debt && hasDue {
                a.maturity = dayFmt.string(from: matDate)
            }
            if a.kind == .deposit {
                a.rate = max(0, numTR(rateStr))
                a.start = dayFmt.string(from: startDate)
                a.maturity = dayFmt.string(from: matDate)
            }
        case .stock, .crypto, .fund:
            let sym: String = a.symbol.trimmingCharacters(in: .whitespaces)
            if a.kind == .stock { a.symbol = sym.uppercased() }
            else if a.kind == .crypto { a.symbol = sym.lowercased() }
            else { a.symbol = sym }
            a.typeName = a.typeName.trimmingCharacters(in: .whitespaces)
            if a.typeName.isEmpty {
                if a.kind == .stock { a.typeName = a.symbol.replacingOccurrences(of: ".IS", with: "") }
                else if a.kind == .crypto { a.typeName = a.symbol }
                else { a.typeName = L("Fon", "Funds") }
            }
            a.price = numTR(priceStr)
        default:
            a.typeName = ""
            a.symbol = ""
            a.price = 0
            a.cur = "tl"
        }
        a.cost = showsCost ? newCost(a) : 0
        return a
    }

    func label(_ t: String) -> some View {
        Text(t).font(.footnote).foregroundStyle(Theme.muted).padding(.top, 10)
    }

    func pick(_ h: StockHit) {
        asset.symbol = h.symbol
        asset.typeName = h.name
        query = ""
        hits = []
        note = L("Fiyat alınıyor...", "Fetching price...")
        let isCrypto: Bool = asset.kind == .crypto
        Task {
            var quote: Quote? = nil
            if isCrypto {
                let m = await store.fetchCryptoPrices([h.symbol])
                if let p = m[h.symbol] { quote = Quote(price: p, cur: "tl") }
            } else {
                quote = await store.fetchQuote(h.symbol)
            }
            if let q = quote {
                priceStr = fmtIn(q.price)
                asset.cur = q.cur
                note = nil
            } else {
                note = L("Fiyat alınamadı, aşağıya elle yazabilirsin.", "Could not fetch the price; you can type it below.")
            }
        }
    }

    @ViewBuilder
    var customSection: some View {
        label(nameLabel)
        TextField(namePlaceholder, text: $asset.typeName)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        if asset.kind == .custom {
            Chips(items: customTypes, selected: asset.typeName) { asset.typeName = $0 }
        }

        label(L("Para birimi", "Currency"))
        curPicker
        if asset.kind == .custom {
            Text(L("Bu türün değeri kurla değişmez, güncel değeri sen yazarsın.", "This type does not change with exchange rates; you enter its current value."))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    var depositSection: some View {
        label(L("Yıllık faiz (%)", "Annual interest (%)"))
        TextField("45", text: $rateStr)
            .keyboardType(.numbersAndPunctuation)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: rateStr) { new in
                let f = formatMoneyInput(new, allowNeg: false)
                if f != new { rateStr = f }
            }
        DatePicker(L("Başlangıç", "Start"), selection: $startDate, displayedComponents: .date)
            .padding(.top, 8)
        DatePicker(L("Vade tarihi", "Maturity date"), selection: $matDate, displayedComponents: .date)
        Text(L("Faiz basit olarak günlük işler ve vadede durur; brüt tutardır, stopaj düşülmez.", "Interest accrues daily as simple interest and stops at maturity; it is gross, no withholding tax is deducted."))
            .font(.caption)
            .foregroundStyle(Theme.muted)
    }

    private var curBinding: Binding<Kind> {
        Binding<Kind>(get: { Kind.fromCur(asset.cur) }, set: { asset.cur = $0.key })
    }

    private var curPicker: some View {
        Seg(items: [Kind.tl, .usd, .eur, .gbp], title: { $0.rawValue }, sel: curBinding)
    }

    private var symbolCaps: TextInputAutocapitalization {
        asset.kind == .stock ? .characters : .never
    }

    private var symbolPlaceholder: String {
        asset.kind == .stock ? "THYAO.IS" : ""
    }

    @ViewBuilder private var searchBlock: some View {
        if searchable {
            label(searchLabel)
            TextField(L("Aramak için yaz", "Type to search"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
        if searching { ProgressView().padding(.vertical, 4) }
        if !hits.isEmpty { hitsList }
        if let note {
            Text(note).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func hitRow(_ h: StockHit) -> some View {
        Button { pick(h) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.name).lineLimit(1)
                    Text(hitSubtitle(h))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hitsList: some View {
        VStack(spacing: 0) {
            ForEach(hits) { h in
                hitRow(h)
                if h.id != hits.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var symbolBlock: some View {
        label(symbolLabel)
        TextField(symbolPlaceholder, text: $asset.symbol)
            .textInputAutocapitalization(symbolCaps)
            .autocorrectionDisabled()
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        label(L("Adı", "Name"))
        textBox(L("Örn. Türk Hava Yolları", "e.g. Turkish Airlines"), $asset.typeName)
    }

    @ViewBuilder private var priceBlock: some View {
        label(priceNote)
        moneyField($priceStr, allowNeg: false)
        curPicker
    }

    @ViewBuilder
    var stockSection: some View {
        searchBlock
        symbolBlock
        priceBlock
    }

    private func moneyField(_ text: Binding<String>, allowNeg: Bool) -> some View {
        TextField("0", text: text)
            .keyboardType(.numbersAndPunctuation)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: text.wrappedValue) { new in
                let f = formatMoneyInput(new, allowNeg: allowNeg)
                if f != new { text.wrappedValue = f }
            }
    }

    private func textBox(_ ph: String, _ text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var placeFields: some View {
        label(L("Konum (ev, yazlık, banka adı...)", "Location (home, summer house, bank name...)"))
        textBox(L("Yeni konum yaz veya aşağıdan seç", "Type a new location or pick one below"), $asset.location)
        Chips(items: locations, selected: asset.location) { asset.location = $0 }
        label(L("Kimin", "Whose"))
        textBox(L("Kişinin adını yaz", "Type the person's name"), $asset.owner)
        Chips(items: owners, selected: asset.owner) { asset.owner = $0 }
        label(L("Tür", "Type"))
        kindPicker
    }

    private var kindPicker: some View {
        Picker(L("Tür", "Type"), selection: $asset.kind) {
            ForEach(Kind.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var showsCustom: Bool {
        asset.kind == .custom || asset.kind == .debt || asset.kind == .deposit
    }

    @ViewBuilder private var debtDueSection: some View {
        Toggle(L("Son ödeme günü var", "Has a due date"), isOn: $hasDue)
            .padding(.top, 8)
        if hasDue {
            DatePicker(L("Son gün", "Due date"), selection: $matDate, displayedComponents: .date)
            Text(L("Son günden 1 gün önce sabah 09:00'da bildirim gelir.", "You get a notification at 9:00 AM, 1 day before the due date."))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var kindSections: some View {
        if showsCustom { customSection }
        if asset.kind == .deposit { depositSection }
        if asset.kind == .debt { debtDueSection }
        if asset.kind.isPriced { stockSection }
    }

    @ViewBuilder private var costFields: some View {
        label(L("Ortalama alış fiyatı, birim başına TL (isteğe bağlı, kâr/zarar için)", "Average purchase price per unit, TRY (optional, for gain/loss)"))
        moneyField($costStr, allowNeg: false)
        if deltaVal > 0 {
            label(L("Bu alımın birim fiyatı, TL", "Unit price of this purchase, TRY"))
            TextField(buyPlaceholder, text: $buyStr)
                .keyboardType(.numbersAndPunctuation)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            Text(L("Boş bırakırsan güncel fiyat kullanılır. Kaydedince ortalama alış fiyatı kendiliğinden güncellenir.", "If left empty, the current price is used. The average purchase price updates automatically when you save."))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        } else if deltaVal < 0 {
            Text(L("Satışta ortalama alış fiyatı değişmez, kalan miktarın kâr/zararı gösterilir.", "Selling does not change the average purchase price; gain/loss is shown for the remaining amount."))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var amountFields: some View {
        label(amountLabel)
        moneyField($amountStr, allowNeg: false)
        label(L("Ekle / çıkar (örn. 2 veya -2)", "Add / remove (e.g. 2 or -2)"))
        moneyField($deltaStr, allowNeg: true)
        if showsCost { costFields }
    }

    @ViewBuilder private var actionButtons: some View {
        if let onSaveAndNew {
            Button {
                onSaveAndNew(built())
                dismiss()
            } label: {
                Text(L("Kaydet, yenisini ekle", "Save and add another"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .background(Theme.line, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!valid)
            .opacity(valid ? 1 : 0.4)
            .padding(.top, 16)
        }
        if let onDelete {
            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: {
                Text(L("Bu varlığı sil", "Delete this asset"))
                    .frame(maxWidth: .infinity)
                    .padding(13)
            }
            .padding(.top, 8)
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            placeFields
            kindSections
            amountFields
            actionButtons
        }
        .padding()
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !searchable || q.count < 2 {
            hits = []
            searching = false
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        if Task.isCancelled { return }
        searching = true
        var r: [StockHit] = []
        if asset.kind == .crypto {
            r = await store.searchCrypto(q)
        } else {
            r = await store.searchStocks(q)
        }
        if Task.isCancelled { return }
        hits = r
        searching = false
        note = r.isEmpty ? L("Sonuç bulunamadı. Sembolü elle yazabilirsin.", "No results. You can type the symbol manually.") : nil
    }

    @ToolbarContentBuilder private var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button(L("Vazgeç", "Cancel")) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button(L("Kaydet", "Save")) {
                onSave(built())
                dismiss()
            }
            .disabled(!valid)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView { formContent }
                .task(id: query) { await runSearch() }
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle(isNew ? L("Varlık ekle", "Add asset") : L("Varlığı düzenle", "Edit asset"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editToolbar }
        }
    }
}
