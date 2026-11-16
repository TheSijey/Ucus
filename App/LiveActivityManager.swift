import ActivityKit
import BackgroundTasks
import Foundation

/// Uygulamanın "şu anki uçuşu". Canlı Etkinlikten bağımsız saklanır; tur bitene kadar uygulamada kalır.
@MainActor
final class FlightSession: ObservableObject {
    static let shared = FlightSession()

    private struct Stored: Codable {
        var query: String
        var state: FlightAttributes.ContentState
    }
    private let key = "currentFlight"

    @Published private(set) var query: String = ""
    @Published private(set) var state: FlightAttributes.ContentState?
    /// Biten son uçuş: tur bittikten sonra da 24 saat kayıt/not eklenebilsin diye.
    @Published private(set) var last: FlightAttributes.ContentState?
    private let lastKey = "lastFlight", lastAtKey = "lastFlightAt"

    /// Takip edilen uçuş, yoksa son 24 saatte biten uçuş.
    var recent: FlightAttributes.ContentState? { state ?? last }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Stored.self, from: data) {
            query = s.query
            state = s.state
        }
        if let at = UserDefaults.standard.object(forKey: lastAtKey) as? Date, Date().timeIntervalSince(at) < 86_400,
           let d = UserDefaults.standard.data(forKey: lastKey),
           let s = try? JSONDecoder().decode(FlightAttributes.ContentState.self, from: d) {
            last = s
        }
        expireIfNeeded()
    }

    func set(query: String, state: FlightAttributes.ContentState) {
        self.query = query
        self.state = state
        if let data = try? JSONEncoder().encode(Stored(query: query, state: state)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        if let s = state, let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: lastKey)
            UserDefaults.standard.set(Date(), forKey: lastAtKey)
            last = s
        }
        query = ""
        state = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Tur bittiyse temizle.
    func expireIfNeeded() {
        if let s = state, Date() >= s.tourEnd {
            DebugLog.add("Tur bitti \(s.flight), uçuş kaldırıldı")
            clear()
        }
    }
}

@MainActor
enum LiveActivityManager {
    static let wakeTaskID = "com.cengiz.ucus.cleanup"

    /// Hâlâ Ada'da olan (bitmemiş) etkinlik.
    static var current: Activity<FlightAttributes>? {
        Activity<FlightAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
    }

    static func start(query: String, state input: FlightAttributes.ContentState) async throws {
        await endAll(reason: "yeni uçuş eklendi", clearSession: false)
        var state = input
        if state.isOutstation {
            // Dış meydan: imza ve otelden çıkış elle girilir; sayaç otelden çıkışa kadar
            state.leaveAt = state.pickupAt.flatMap { $0 > Date() ? $0 : nil }
        } else {
            // Aynı uçuş daha önce eklendiyse ve EOBT öne çekildiyse eski (daha geç) imza kalır.
            state.signOn = SignOnMemory.resolve(flight: state.flight, newSignOn: state.signOn)
            state.leaveAt = SignOnMemory.leave(for: state.signOn, minutes: AppSettings.leaveMinutes)
        }

        FlightSession.shared.set(query: query, state: state)
        if Date() < state.hideAt, ActivityAuthorizationInfo().areActivitiesEnabled {
            let content = ActivityContent(state: state, staleDate: state.hideAt)
            let activity = try Activity.request(attributes: FlightAttributes(query: query), content: content, pushType: nil)
            ActivityObserver.watch(activity)
        }
        DebugLog.add("Başlatıldı \(state.flight) · imza \(state.signOn.formatted(.dateTime.hour().minute())) · stand \(state.stand)")

        await NotificationManager.scheduleFor(state)
        scheduleNextWake()
        WidgetSync.push()
    }

    /// Durumu kaydeder; etkinlik hâlâ Ada'daysa onu da günceller.
    static func apply(_ state: FlightAttributes.ContentState) async {
        FlightSession.shared.set(query: FlightSession.shared.query, state: state)
        if let a = current {
            await a.update(ActivityContent(state: state, staleDate: state.hideAt))
        }
        WidgetSync.push()
    }

    /// Kullanıcı kaldırdı (ya da yeni uçuş): etkinlik hemen kapanır.
    static func endAll(reason: String = "kullanıcı kaldırdı", clearSession: Bool = true) async {
        NotificationManager.cancelLeave()
        for a in Activity<FlightAttributes>.activities {
            DebugLog.add("Kapatılıyor \(a.content.state.flight): \(reason)")
            await a.end(nil, dismissalPolicy: .immediate)
        }
        if clearSession { FlightSession.shared.clear() }
        WidgetSync.push()
    }

    /// İmza + 30: Ada'dan kalkar, kilit ekranında tur sonuna kadar (iOS en fazla 4 sa) kalır.
    /// Tur bitince her şey kapanır.
    static func endExpired() async {
        let now = Date()
        for a in Activity<FlightAttributes>.activities {
            let s = a.content.state
            if now >= s.tourEnd {
                await a.end(nil, dismissalPolicy: .immediate)
            } else if now >= s.hideAt, a.activityState == .active || a.activityState == .stale {
                DebugLog.add("İmza+30 \(s.flight): Ada'dan kaldırıldı, kilit ekranında kalıyor")
                await a.end(ActivityContent(state: s, staleDate: nil),
                            dismissalPolicy: .after(min(s.tourEnd, now.addingTimeInterval(4 * 3600))))
            }
        }
        FlightSession.shared.expireIfNeeded()
    }

    /// Görünümü yeniden çizdirir (çıkış saati geçtiyse Ada imza sayacına geçer).
    static func refreshPhase() async {
        await endExpired()
        if var s = FlightSession.shared.state {
            if let leave = s.leaveAt, Date() >= leave { s.leaveAt = nil }
            await apply(s)
        }
        scheduleNextWake()
        WidgetSync.push()
    }

    /// iOS'tan bir sonraki önemli anda (çıkış, imza+30, tur sonu) uygulamayı kısa süre uyandırmasını ister.
    static func scheduleNextWake() {
        guard let s = FlightSession.shared.state else { return }
        let next = [s.leaveAt, s.hideAt, s.tourEnd].compactMap { $0 }.filter { $0 > Date() }.min()
        guard let next else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: wakeTaskID)
        let request = BGAppRefreshTaskRequest(identifier: wakeTaskID)
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
enum FlightRefresher {
    /// Şu anki uçuşu CDM ve diğer kaynaklardan tekrar çeker.
    /// İmza: EOBT öne çekildiyse eski (geç) imza kalır, ertelendiyse yeni imzaya geçer.
    /// - Returns: hata mesajı; başarılıysa nil.
    @discardableResult
    static func refreshActive() async -> String? {
        await LiveActivityManager.endExpired()
        let session = FlightSession.shared
        guard let old = session.state, !session.query.isEmpty else {
            DebugLog.add("Yenile: etkin uçuş yok")
            return L("Etkin uçuş yok.", "No active flight.")
        }
        DebugLog.add("Yenile başladı \(old.flight)")
        do {
            var state = try await FlightLoader.load(query: session.query, plannedDay: old.isOutstation ? old.eobt : nil,
                                                    outstation: old.isOutstation)
            if state.isOutstation {
                // İmza elle girilmediyse kalkış öne çekilince eski (geç) tahmin kalır
                if state.signOnManual != true { state.signOn = max(old.signOn, state.signOn) }
                if state.registration.isEmpty { state.registration = old.registration }
                state.leaveAt = state.pickupAt.flatMap { $0 > Date() ? $0 : nil }
            } else {
                state.signOn = max(old.signOn, state.signOn)
                SignOnMemory.remember(flight: state.flight, signOn: state.signOn)
                state.leaveAt = SignOnMemory.leave(for: state.signOn, minutes: AppSettings.leaveMinutes)
            }
            // CDM uçuş kalktıktan sonra bilgi vermeyebilir: boş gelenleri eskiden koru
            if state.turn == nil { state.turn = old.turn }
            if state.inbound == nil { state.inbound = old.inbound }
            if state.leaveAt != old.leaveAt || state.pickupAt != old.pickupAt {
                await NotificationManager.scheduleFor(state)
            }
            await LiveActivityManager.apply(state)
            DebugLog.add("Yenile tamam · stand \(state.stand) · imza \(state.signOn.formatted(.dateTime.hour().minute()))")
            LiveActivityManager.scheduleNextWake()
            return nil
        } catch {
            DebugLog.add("Yenile hata: \(error.localizedDescription.prefix(80))")
            return error.localizedDescription
        }
    }
}

/// Bir uçuş için verilen en geç imza saatini hatırlar (Ada'dan kaldırılıp yeniden eklense bile).
enum SignOnMemory {
    private static let key = "signOnMemory"   // [uçuş: zaman damgası]

    private static var store: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Kayıtlı imza 12 saatten yakınsa (aynı uçuş günü) ikisinden geç olanı döndürür ve kaydeder.
    static func resolve(flight: String, newSignOn: Date) -> Date {
        var result = newSignOn
        if let t = store[flight] {
            let old = Date(timeIntervalSince1970: t)
            if abs(old.timeIntervalSince(newSignOn)) < 12 * 3600 { result = max(old, newSignOn) }
        }
        remember(flight: flight, signOn: result)
        return result
    }

    static func remember(flight: String, signOn: Date) {
        var s = store.filter { Date().timeIntervalSince1970 - $0.value < 2 * 86_400 }   // 2 günden eskileri sil
        s[flight] = signOn.timeIntervalSince1970
        store = s
    }

    /// İmza - çıkış süresi; geçmişse ya da ayar kapalıysa nil.
    static func leave(for signOn: Date, minutes: Int) -> Date? {
        guard minutes > 0 else { return nil }
        let leave = signOn.addingTimeInterval(-Double(minutes) * 60)
        return leave > Date() ? leave : nil
    }
}
