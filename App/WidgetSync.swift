import Foundation
import WidgetKit

/// Uygulamadaki güncel durumu widget'a aktarır.
@MainActor
enum WidgetSync {
    static func push() {
        if let s = FlightSession.shared.state, s.tourEnd > Date() {
            SharedStore.active = .init(flight: s.flight, registration: s.registration, stand: s.stand,
                                       gate: s.gate, destination: s.destination, signOn: s.signOn,
                                       leaveAt: s.upcomingLeave(), hideAt: s.tourEnd,
                                       timeline: s.dayTimeline)
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
