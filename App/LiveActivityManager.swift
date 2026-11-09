import ActivityKit
import BackgroundTasks
import Foundation

@MainActor
enum LiveActivityManager {
    static let cleanupTaskID = "com.cengiz.ucus.cleanup"

    static var current: Activity<FlightAttributes>? { Activity<FlightAttributes>.activities.first }

    static func start(query: String, state: FlightAttributes.ContentState) async throws {
        await endAll()
        let content = ActivityContent(state: state, staleDate: state.hideAt)
        _ = try Activity.request(attributes: FlightAttributes(query: query), content: content, pushType: nil)
        scheduleCleanup(at: state.hideAt)
    }

    static func update(_ activity: Activity<FlightAttributes>, with state: FlightAttributes.ContentState) async {
        await activity.update(ActivityContent(state: state, staleDate: state.hideAt))
    }

    static func endAll() async {
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

    /// iOS'tan o saatte uygulamayı kısa süre uyandırmasını ister (iOS saati biraz kaydırabilir).
    static func scheduleCleanup(at date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: cleanupTaskID)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
enum FlightRefresher {
    /// Açık Canlı Etkinliği CDM'den tekrar çekip günceller. İmza saati sabit kalır.
    static func refreshActive() async {
        await LiveActivityManager.endExpired()
        guard let activity = LiveActivityManager.current else { return }
        do {
            var state = try await CDMFetcher.shared.fetch(query: activity.attributes.query)
            state.signOn = activity.content.state.signOn
            await LiveActivityManager.update(activity, with: state)
        } catch {
            // Çekemezse eski bilgi kalır.
        }
    }
}
