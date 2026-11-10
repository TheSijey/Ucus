import ActivityKit
import BackgroundTasks
import Foundation

@MainActor
enum LiveActivityManager {
    static let wakeTaskID = "com.cengiz.ucus.cleanup"

    static var current: Activity<FlightAttributes>? { Activity<FlightAttributes>.activities.first }

    static func start(query: String, state input: FlightAttributes.ContentState) async throws {
        await endAll()
        var state = input
        let minutes = AppSettings.leaveMinutes
        if minutes > 0 {
            let leave = state.signOn.addingTimeInterval(-Double(minutes) * 60)
            state.leaveAt = leave > Date() ? leave : nil
        } else {
            state.leaveAt = nil
        }

        let content = ActivityContent(state: state, staleDate: state.hideAt)
        _ = try Activity.request(attributes: FlightAttributes(query: query), content: content, pushType: nil)

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

    static func endAll() async {
        NotificationManager.cancelLeave()
        for a in Activity<FlightAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// İmza + 30 dk geçmişse kapat.
    static func endExpired() async {
        for a in Activity<FlightAttributes>.activities where Date() >= a.content.state.hideAt {
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
    /// Açık Canlı Etkinliği CDM'den tekrar çekip günceller. İmza ve çıkış saatleri sabit kalır.
    static func refreshActive() async {
        await LiveActivityManager.endExpired()
        guard let activity = LiveActivityManager.current else { return }
        do {
            var state = try await FlightLoader.load(query: activity.attributes.query)
            let old = activity.content.state
            state.signOn = old.signOn
            state.leaveAt = old.upcomingLeave()
            await LiveActivityManager.update(activity, with: state)
        } catch {
            // Çekemezse eski bilgi kalır.
        }
    }
}
