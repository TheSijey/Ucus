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
}

struct AlertPrices: Codable {
    var gram: Double
    var ons: Double
    var usd: Double
    var eur: Double
    var gbp: Double
    var at: String?

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
    case gram, ons, usd, eur, gbp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gram: return L("Gram altın", "Gold gram")
        case .ons: return L("Ons altın", "Gold ounce")
        case .usd: return L("Dolar/TL", "USD/TRY")
        case .eur: return L("Euro/TL", "EUR/TRY")
        case .gbp: return L("Sterlin/TL", "GBP/TRY")
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
        let r = try JSONDecoder().decode(AlertsReply.self, from: data)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
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

    func add(metric: AlertMetric, dir: AlertDir, value: Double) async {
        let lang: String = isEnglish() ? "en" : "tr"
        let a = PriceAlert(id: UUID().uuidString, metric: metric.rawValue, dir: dir.rawValue,
                           value: value, active: true, firedAt: nil, firedPrice: nil, lang: lang)
        await save(alerts + [a])
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
    let digits: Int = (m == "gram" || m == "ons") ? 0 : 4
    return v.formatted(.number.precision(.fractionLength(0...digits)))
}

struct AlertRow: View {
    let alert: PriceAlert
    let price: Double?
    let onToggle: () -> Void

    private var metric: AlertMetric { AlertMetric(rawValue: alert.metric) ?? .gram }
    private var dir: AlertDir { AlertDir(rawValue: alert.dir) ?? .above }

    private var title: String {
        "\(metric.label) · \(dir.label) \(metric.symbol)\(alertNum(alert.value, alert.metric))"
    }

    private var detail: String {
        if let fp = alert.firedPrice, !alert.active {
            return L("Gerçekleşti: \(metric.symbol)\(alertNum(fp, alert.metric))", "Triggered at \(metric.symbol)\(alertNum(fp, alert.metric))")
        }
        guard let p = price else { return "" }
        return L("Şu an \(metric.symbol)\(alertNum(p, alert.metric))", "Now \(metric.symbol)\(alertNum(p, alert.metric))")
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

    init(store: Store) {
        _model = StateObject(wrappedValue: AlertsModel(store: store))
    }

    private var currentText: String {
        guard let p = model.prices?.value(metric.rawValue) else { return "" }
        return L("Şu an \(metric.symbol)\(alertNum(p, metric.rawValue))", "Now \(metric.symbol)\(alertNum(p, metric.rawValue))")
    }

    private var addSection: some View {
        Section(L("Yeni alarm", "New alert")) {
            Picker(L("Ne", "What"), selection: $metric) {
                ForEach(AlertMetric.allCases) { Text($0.label).tag($0) }
            }
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
                Task { await model.add(metric: metric, dir: dir, value: v) }
            }
            .disabled(numTR(valueStr) <= 0 || model.busy)
        }
    }

    private var listSection: some View {
        Section(L("Alarmlarım", "My alerts")) {
            if model.alerts.isEmpty {
                Text(L("Henüz alarm yok.", "No alerts yet.")).foregroundStyle(Theme.muted)
            }
            ForEach(model.alerts) { a in
                AlertRow(alert: a, price: model.prices?.value(a.metric)) {
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
