import ActivityKit
import Foundation
import WidgetKit

/// Uygulamadaki güncel durumu widget'a aktarır.
@MainActor
enum WidgetSync {
    static func push() {
        if let s = Activity<FlightAttributes>.activities.first(where: { $0.activityState == .active })?.content.state,
           s.hideAt > Date() {
            SharedStore.active = .init(flight: s.flight, registration: s.registration, stand: s.stand,
                                       gate: s.gate, destination: s.destination, signOn: s.signOn,
                                       leaveAt: s.upcomingLeave(), hideAt: s.hideAt,
                                       timeline: s.dayTimeline)
        } else if let old = SharedStore.active, let end = old.timeline?.end, end > Date() {
            // Ada kapandı ama günün akışı sürüyor: widget'ta çizelge kalsın.
            SharedStore.active = old
        } else {
            SharedStore.active = nil
        }
        if let data = UserDefaults.standard.data(forKey: "plannedFlights"),
           let list = try? JSONDecoder().decode([PlannedFlight].self, from: data) {
            SharedStore.planned = list.sorted { $0.date < $1.date }.map { .init(flight: $0.flight, date: $0.date) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
