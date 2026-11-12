import ActivityKit
import BackgroundTasks
import Foundation

@MainActor
enum LiveActivityManager {
    static let wakeTaskID = "com.cengiz.ucus.cleanup"

    static var current: Activity<FlightAttributes>? { Activity<FlightAttributes>.activities.first }

    static func start(query: String, state input: FlightAttributes.ContentState) async throws {
        await endAll(reason: "yeni uçuş eklendi")
        var state = input
        // Aynı uçuş daha önce eklendiyse ve EOBT öne çekildiyse eski (daha geç) imza kalır.
        state.signOn = SignOnMemory.resolve(flight: state.flight, newSignOn: state.signOn)
        let minutes = AppSettings.leaveMinutes
        state.leaveAt = SignOnMemory.leave(for: state.signOn, minutes: minutes)

        let content = ActivityContent(state: state, staleDate: state.hideAt)
        let activity = try Activity.request(attributes: FlightAttributes(query: query), content: content, pushType: nil)
        ActivityObserver.watch(activity)
        DebugLog.add("Başlatıldı \(state.flight) · imza \(state.signOn.formatted(.dateTime.hour().minute())) · stand \(state.stand)")

        if let leave = state.leaveAt {
            await NotificationManager.scheduleLeave(flight: state.flight, at: leave, minutesBeforeSignOn: minutes)
        } else {
            NotificationManager.cancelLeave()
        }
        scheduleNextWake()
    }

    static func update(_ activity: Activity<FlightAttributes>, with state: FlightAttributes.ContentState) async {
        await activity.update(ActivityContent(state: state, staleDate: state.hideAt))
    }

    static func endAll(reason: String = "kullanıcı kaldırdı") async {
        NotificationManager.cancelLeave()
        for a in Activity<FlightAttributes>.activities {
            DebugLog.add("Kapatılıyor \(a.content.state.flight): \(reason)")
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// İmza + 30 dk geçmişse kapat.
    static func endExpired() async {
        for a in Activity<FlightAttributes>.activities where Date() >= a.content.state.hideAt {
            DebugLog.add("Süresi doldu \(a.content.state.flight) (imza+30: \(a.content.state.hideAt.formatted(.dateTime.hour().minute())))")
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Görünümü yeniden çizdirir (çıkış saati geçtiyse Ada imza sayacına geçer).
    static func refreshPhase() async {
        await endExpired()
        for a in Activity<FlightAttributes>.activities {
            var s = a.content.state
            if let leave = s.leaveAt, Date() >= leave { s.leaveAt = nil }
            await update(a, with: s)
        }
        scheduleNextWake()
    }

    /// iOS'tan bir sonraki önemli anda (çıkış ya da kaybolma) uygulamayı kısa süre uyandırmasını ister.
    /// iOS bunu birkaç dakika kaydırabilir.
    static func scheduleNextWake() {
        guard let s = current?.content.state else { return }
        let next = [s.leaveAt, s.hideAt].compactMap { $0 }.filter { $0 > Date() }.min()
        guard let next else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: wakeTaskID)
        let request = BGAppRefreshTaskRequest(identifier: wakeTaskID)
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
enum FlightRefresher {
    /// Açık Canlı Etkinliği CDM'den tekrar çekip günceller.
    /// İmza saati: EOBT öne çekildiyse eski (geç) imza kalır, ertelendiyse yeni imzaya geçer.
    /// - Returns: hata mesajı; başarılıysa nil.
    @discardableResult
    static func refreshActive() async -> String? {
        await LiveActivityManager.endExpired()
        guard let activity = LiveActivityManager.current else {
            DebugLog.add("Yenile: Ada'da etkin uçuş yok")
            return "Ada'da uçuş yok."
        }
        DebugLog.add("Yenile başladı \(activity.content.state.flight) · durum \(String(describing: activity.activityState))")
        do {
            var state = try await FlightLoader.load(query: activity.attributes.query)
            let old = activity.content.state
            state.signOn = max(old.signOn, state.signOn)
            SignOnMemory.remember(flight: state.flight, signOn: state.signOn)

            let minutes = AppSettings.leaveMinutes
            state.leaveAt = SignOnMemory.leave(for: state.signOn, minutes: minutes)   // geçmişse nil
            if state.leaveAt != old.leaveAt {
                if let leave = state.leaveAt {
                    await NotificationManager.scheduleLeave(flight: state.flight, at: leave, minutesBeforeSignOn: minutes)
                } else {
                    NotificationManager.cancelLeave()
                }
            }
            await LiveActivityManager.update(activity, with: state)

            // Güvence: etkinlik bir sebeple kapandıysa aynı bilgilerle yeniden aç.
            try? await Task.sleep(for: .milliseconds(300))
            if activity.activityState != .active || LiveActivityManager.current == nil {
                DebugLog.add("Yenile sonrası etkinlik kapalı (\(String(describing: activity.activityState))) → yeniden açılıyor")
                let content = ActivityContent(state: state, staleDate: state.hideAt)
                if let a = try? Activity.request(attributes: activity.attributes, content: content, pushType: nil) {
                    ActivityObserver.watch(a)
                }
            }
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
