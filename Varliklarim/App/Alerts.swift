import SwiftUI
import UIKit
import UserNotifications

// MARK: - Fiyat alarmları (sunucu: Cloudflare Worker)

struct PriceAlert: Codable, Identifiable, Equatable {
    var id: String
    var metric: String
    var dir: String
    var value: Double
    var active: Bool
    var firedAt: String?
    var firedPrice: Double?
    var lang: String
    var symbol: String?
    var name: String?
}

struct SymQuote: Codable {
    var p: Double
    var cur: String
}

func curSign(_ c: String) -> String {
    switch c.uppercased() {
    case "TRY": return "₺"
    case "USD": return "$"
    case "EUR": return "€"
    case "GBP": return "£"
    default: return ""
    }
}

struct AlertPrices: Codable {
    var gram: Double
    var ons: Double
    var usd: Double
    var eur: Double
    var gbp: Double
    var at: String?
    var syms: [String: SymQuote]?

    func value(_ m: String) -> Double {
        switch m {
        case "ons": return ons
        case "usd": return usd
        case "eur": return eur
        case "gbp": return gbp
        default: return gram
        }
    }
}

enum AlertMetric: String, CaseIterable, Identifiable {
    case gram, ons, usd, eur, gbp, sym
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gram: return L("Gram altın", "Gold gram")
        case .ons: return L("Ons altın (dolar)", "Gold ounce (USD)")
        case .usd: return L("Dolar/TL", "USD/TRY")
        case .eur: return L("Euro/TL", "EUR/TRY")
        case .gbp: return L("Sterlin/TL", "GBP/TRY")
        case .sym: return L("Başka bir değer (hisse, kripto, gümüş...)", "Other (stock, crypto, silver...)")
        }
    }
    var symbol: String { self == .ons ? "$" : "₺" }
}

enum AlertDir: String, CaseIterable, Identifiable {
    case below, above
    var id: String { rawValue }
    var label: String {
        self == .below ? L("Altına inince", "Falls below") : L("Üstüne çıkınca", "Rises above")
    }
}

struct AlertsReply: Decodable {
    var alerts: [PriceAlert]?
    var devices: Int?
    var prices: AlertPrices?
    var sent: Int?
    var error: String?
    var quote: QuoteReply?
}

struct QuoteReply: Decodable {
    var symbol: String
    var p: Double
    var cur: String
    var name: String?
}

enum AlertsAPI {
    static var baseURL: String {
        let s = (Bundle.main.object(forInfoDictionaryKey: "AlertsURL") as? String) ?? ""
        return s.hasPrefix("https://") ? s : ""
    }

    static func call(_ path: String, _ body: [String: Any]) async throws -> AlertsReply {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else {
            throw CloudError.message(L("Alarm sunucusu henüz kurulmadı.", "The alert server is not set up yet."))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let r = try? JSONDecoder().decode(AlertsReply.self, from: data) else {
            let txt: String = String(data: data.prefix(160), encoding: .utf8) ?? ""
            throw CloudError.message(L("Sunucu yanıtı okunamadı (HTTP \(code)). \(txt)", "Could not read the server reply (HTTP \(code)). \(txt)"))
        }
        if code == 401 {
            throw CloudError.message(L("Oturum doğrulanamadı, çıkış yapıp tekrar gir.", "Session could not be verified; sign out and in again."))
        }
        if let e = r.error { throw CloudError.message(e) }
        return r
    }
}

@MainActor
final class AlertsModel: ObservableObject {
    @Published var alerts: [PriceAlert] = []
    @Published var prices: AlertPrices?
    @Published var devices: Int = 0
    @Published var busy = false
    @Published var message: String?
    @Published var permissionDenied = false

    let store: Store

    init(store: Store) { self.store = store }

    private func base() async throws -> [String: Any] {
        var b: [String: Any] = ["idToken": try await store.freshToken()]
        if let t = UserDefaults.standard.string(forKey: "apnsToken") {
            b["device"] = ["token": t, "sandbox": false]
        }
        return b
    }

    private func apply(_ r: AlertsReply) {
        if let a = r.alerts { alerts = a }
        if let p = r.prices { prices = p }
        if let d = r.devices { devices = d }
    }

    func askPermission() async {
        let c = UNUserNotificationCenter.current()
        let ok: Bool = (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permissionDenied = !ok
        if ok { UIApplication.shared.registerForRemoteNotifications() }
    }

    func load() async {
        busy = true
        defer { busy = false }
        do {
            apply(try await AlertsAPI.call("/sync", try await base()))
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func save(_ list: [PriceAlert]) async {
        let old = alerts
        alerts = list
        do {
            var b = try await base()
            let enc = try JSONEncoder().encode(list)
            b["alerts"] = try JSONSerialization.jsonObject(with: enc)
            apply(try await AlertsAPI.call("/alerts", b))
            message = nil
        } catch {
            alerts = old
            message = error.localizedDescription
        }
    }

    func add(metric: AlertMetric, dir: AlertDir, value: Double, symbol: String? = nil, name: String? = nil) async {
        let lang: String = isEnglish() ? "en" : "tr"
        let a = PriceAlert(id: UUID().uuidString, metric: metric.rawValue, dir: dir.rawValue,
                           value: value, active: true, firedAt: nil, firedPrice: nil, lang: lang,
                           symbol: symbol, name: name)
        await save(alerts + [a])
    }

    func quote(_ symbol: String) async -> QuoteReply? {
        guard var b = try? await base() else { return nil }
        b["symbol"] = symbol
        return (try? await AlertsAPI.call("/quote", b))?.quote
    }

    /// Yahoo'da her türlü değeri arar: hisse, döviz, kripto, emtia, endeks
    func search(_ q: String) async -> [StockHit] {
        let text = q.trimmingCharacters(in: .whitespaces)
        if text.count < 2 { return [] }
        var comps = URLComponents(string: "https://query2.finance.yahoo.com/v1/finance/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "quotesCount", value: "12"),
            URLQueryItem(name: "newsCount", value: "0")
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = o["quotes"] as? [[String: Any]] else { return [] }
        var out: [StockHit] = []
        for qd in quotes {
            guard let sym = qd["symbol"] as? String else { continue }
            let name: String = (qd["shortname"] as? String) ?? (qd["longname"] as? String) ?? sym
            let type: String = (qd["typeDisp"] as? String) ?? (qd["quoteType"] as? String) ?? ""
            let ex: String = (qd["exchDisp"] as? String) ?? ""
            out.append(StockHit(symbol: sym, name: name, exchange: [type, ex].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        return out
    }

    func toggle(_ a: PriceAlert) async {
        var list = alerts
        guard let i = list.firstIndex(where: { $0.id == a.id }) else { return }
        list[i].active.toggle()
        if list[i].active { list[i].firedAt = nil; list[i].firedPrice = nil }
        await save(list)
    }

    func remove(_ a: PriceAlert) async {
        await save(alerts.filter { $0.id != a.id })
    }

    func test() async {
        busy = true
        defer { busy = false }
        do {
            var b = try await base()
            b["lang"] = isEnglish() ? "en" : "tr"
            let r = try await AlertsAPI.call("/test", b)
            let n: Int = r.sent ?? 0
            message = n > 0 ? L("Deneme bildirimi gönderildi.", "Test notification sent.")
                            : L("Kayıtlı cihaz yok. Bildirim iznini kontrol et.", "No registered device. Check notification permission.")
        } catch {
            message = error.localizedDescription
        }
    }
}

func alertNum(_ v: Double, _ m: String) -> String {
    var digits: Int = (m == "gram" || m == "ons") ? 0 : 4
    if m == "sym" { digits = v >= 1000 ? 0 : (v >= 1 ? 2 : 6) }
    return v.formatted(.number.precision(.fractionLength(0...digits)))
}

struct AlertRow: View {
    let alert: PriceAlert
    let prices: AlertPrices?
    let onToggle: () -> Void

    private var metric: AlertMetric { AlertMetric(rawValue: alert.metric) ?? .gram }
    private var dir: AlertDir { AlertDir(rawValue: alert.dir) ?? .above }

    private var symQuote: SymQuote? {
        guard metric == .sym, let s = alert.symbol else { return nil }
        return prices?.syms?[s]
    }

    private var sign: String {
        if metric == .sym { return curSign(symQuote?.cur ?? "") }
        return metric.symbol
    }

    private var name: String {
        if metric == .sym {
            let n: String = alert.name ?? ""
            return n.isEmpty ? (alert.symbol ?? "") : n
        }
        return metric.label
    }

    private var price: Double? {
        if metric == .sym { return symQuote?.p }
        return prices?.value(alert.metric)
    }

    private var title: String {
        "\(name) · \(dir.label) \(sign)\(alertNum(alert.value, alert.metric))"
    }

    private var detail: String {
        if let fp = alert.firedPrice, !alert.active {
            return L("Gerçekleşti: \(sign)\(alertNum(fp, alert.metric))", "Triggered at \(sign)\(alertNum(fp, alert.metric))")
        }
        guard let p = price else {
            return metric == .sym ? L("Fiyat ilk kontrolde gelecek", "Price arrives at the next check") : ""
        }
        return L("Şu an \(sign)\(alertNum(p, alert.metric))", "Now \(sign)\(alertNum(p, alert.metric))")
    }

    private var binding: Binding<Bool> {
        Binding<Bool>(get: { alert.active }, set: { _ in onToggle() })
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
    }
}

struct AlertsView: View {
    @StateObject private var model: AlertsModel
    @Environment(\.dismiss) private var dismiss
    @State private var metric: AlertMetric = .gram
    @State private var dir: AlertDir = .below
    @State private var valueStr = ""
    @State private var query = ""
    @State private var hits: [StockHit] = []
    @State private var picked: StockHit?
    @State private var pickedQuote: QuoteReply?

    init(store: Store) {
        _model = StateObject(wrappedValue: AlertsModel(store: store))
    }

    private var currentText: String {
        if metric == .sym {
            guard let q = pickedQuote else { return "" }
            return L("Şu an \(curSign(q.cur))\(alertNum(q.p, "sym"))", "Now \(curSign(q.cur))\(alertNum(q.p, "sym"))")
        }
        guard let p = model.prices?.value(metric.rawValue) else { return "" }
        return L("Şu an \(metric.symbol)\(alertNum(p, metric.rawValue))", "Now \(metric.symbol)\(alertNum(p, metric.rawValue))")
    }

    private var addSection: some View {
        Section(L("Yeni alarm", "New alert")) {
            Picker(L("Ne", "What"), selection: $metric) {
                ForEach(AlertMetric.allCases) { Text($0.label).tag($0) }
            }
            if metric == .sym { symbolPicker }
            Picker(L("Ne zaman", "When"), selection: $dir) {
                ForEach(AlertDir.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField(L("Değer (örn. 4.300 veya 34,5)", "Value (e.g. 4.300 or 34,5)"), text: $valueStr)
                .keyboardType(.numbersAndPunctuation)
                .onChange(of: valueStr) { _, new in
                    let f = formatMoneyInput(new, allowNeg: false)
                    if f != new { valueStr = f }
                }
            if !currentText.isEmpty {
                Text(currentText).font(.caption).foregroundStyle(Theme.muted)
            }
            Button(L("Alarm ekle", "Add alert")) {
                let v: Double = numTR(valueStr)
                valueStr = ""
                let s: String? = metric == .sym ? picked?.symbol : nil
                let n: String? = metric == .sym ? picked?.name : nil
                Task { await model.add(metric: metric, dir: dir, value: v, symbol: s, name: n) }
            }
            .disabled(!canAdd)
        }
    }

    private var canAdd: Bool {
        if numTR(valueStr) <= 0 || model.busy { return false }
        if metric == .sym && picked == nil { return false }
        return true
    }

    @ViewBuilder private var symbolPicker: some View {
        if let p = picked {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.subheadline.weight(.semibold))
                    Text(p.symbol).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button(L("Değiştir", "Change")) {
                    picked = nil
                    pickedQuote = nil
                }
            }
        } else {
            TextField(L("Ara: THY, bitcoin, gümüş, BIST 100...", "Search: Apple, bitcoin, silver, S&P 500..."), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            ForEach(hits) { h in
                Button {
                    picked = h
                    hits = []
                    query = ""
                    Task { pickedQuote = await model.quote(h.symbol) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.name).lineLimit(1)
                        Text("\(h.symbol) · \(h.exchange)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }
        }
    }

    private var listSection: some View {
        Section(L("Alarmlarım", "My alerts")) {
            if model.alerts.isEmpty {
                Text(L("Henüz alarm yok.", "No alerts yet.")).foregroundStyle(Theme.muted)
            }
            ForEach(model.alerts) { a in
                AlertRow(alert: a, prices: model.prices) {
                    Task { await model.toggle(a) }
                }
                .swipeActions {
                    Button(L("Sil", "Delete"), role: .destructive) {
                        Task { await model.remove(a) }
                    }
                }
            }
        }
    }

    private var infoSection: some View {
        Section {
            if model.permissionDenied {
                Text(L("Bildirim izni kapalı. iPhone Ayarlar > Varlıklarım > Bildirimler'den aç.", "Notifications are off. Turn them on in iPhone Settings > Varlıklarım > Notifications."))
                    .foregroundStyle(.orange)
            }
            if let m = model.message {
                Text(m).foregroundStyle(Theme.muted)
            }
            Button(L("Deneme bildirimi gönder", "Send test notification")) {
                Task { await model.test() }
            }
            .disabled(model.busy)
            Text(L("Fiyatlar 5 dakikada bir kontrol edilir. Hedefe gelince bildirim bir kez gelir ve alarm kapanır; tekrar açabilirsin. Alarmlar hesabına bağlıdır, aynı hesapla giren her cihaza bildirim gider.", "Prices are checked every 5 minutes. When a target is reached you get one notification and the alert turns off; you can turn it back on. Alerts belong to your account and go to every device signed in with it."))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                addSection
                listSection
                infoSection
            }
            .navigationTitle(L("Fiyat alarmları", "Price alerts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Kapat", "Close")) { dismiss() } }
            }
            .task {
                await model.askPermission()
                await model.load()
            }
            .refreshable { await model.load() }
            .task(id: query) {
                let q: String = query
                if q.trimmingCharacters(in: .whitespaces).count < 2 { hits = []; return }
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                let r: [StockHit] = await model.search(q)
                if !Task.isCancelled { hits = r }
            }
            .onReceive(NotificationCenter.default.publisher(for: .apnsToken)) { _ in
                Task { await model.load() }
            }
        }
    }
}

struct AlertsCard: View {
    @ObservedObject var store: Store
    @State private var open = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Fiyat alarmları", "Price alerts")).font(.headline)
                Text(L("Gram altın veya kur hedefe gelince bildirim al.", "Get notified when gold or exchange rates reach a target."))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Button {
                    open = true
                } label: {
                    Label(L("Alarmları aç", "Open alerts"), systemImage: "bell.badge")
                }
            }
        }
        .sheet(isPresented: $open) { AlertsView(store: store) }
    }
}
