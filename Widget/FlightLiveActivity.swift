import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct UcusWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
        NextFlightWidget()
    }
}

struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightAttributes.self) { context in
            LockScreenView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "ucus://refresh"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.flight).font(.title3.bold())
                        Text(Display.text(s.registration)).font(.headline).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("STAND").font(.caption2).foregroundStyle(.secondary)
                        Text(Display.text(s.stand)).font(.title2.bold()).foregroundStyle(.cyan)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Gate \(Display.text(s.gate))")
                        Spacer()
                        PhaseCountdown(state: s)
                            .frame(maxWidth: 130, alignment: .trailing)
                        Link(destination: URL(string: "ucus://refresh")!) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 6)
                    }
                    .font(.subheadline.monospacedDigit())
                }
            } compactLeading: {
                VStack(alignment: .leading, spacing: -1) {
                    Text(s.flight)
                        .font(.system(size: 11, weight: .bold))
                    PhaseCountdown(state: s, showLabel: false, showIcon: true)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: 60, alignment: .leading)
                }
                .monospacedDigit()
            } compactTrailing: {
                Text("\(s.shortRegistration) \(Display.text(s.stand))")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
            } minimal: {
                Text(Display.text(s.stand))
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
            }
        }
        .supplementalActivityFamilies([.small])   // Apple Watch Akıllı Yığın
    }
}

struct LockScreenView: View {
    let state: FlightAttributes.ContentState
    let stale: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            watchView
        } else {
            fullView
        }
    }

    // Saat ve küçük alanlar için
    private var watchView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(state.flight).bold()
                Spacer()
                Text(Display.text(state.stand)).bold().foregroundStyle(.cyan)
            }
            Text("\(Display.text(state.registration)) · Gate \(Display.text(state.gate))")
                .font(.caption)
            PhaseCountdown(state: state)
                .font(.caption.bold())
        }
        .padding(12)
        .foregroundStyle(.white)
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: state.inbound == nil ? 10 : 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.flight).font(.title3.bold())
                if !state.destination.isEmpty {
                    Image(systemName: "arrow.right").font(.caption)
                    Text(state.destination).font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("STAND").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Text(Display.text(state.stand)).font(.title2.bold()).foregroundStyle(.cyan)
                }
            }
            HStack {
                Text(Display.text(state.registration)).font(.headline)
                Text(state.aircraftType).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("Gate \(Display.text(state.gate))").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            if let ib = state.inbound {
                InboundLine(info: ib)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let leave = state.upcomingLeave() {
                    Image(systemName: "house.fill").font(.caption).foregroundStyle(.green)
                    Countdown(target: leave)
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                        .frame(maxWidth: 78, alignment: .leading)
                }
                Text("İmzaya").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                Countdown(target: state.signOn)
                    .font(.title3.bold())
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: 78, alignment: .leading)
                Spacer(minLength: 4)
                Text("RWY").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                Text(Display.text(state.runway)).font(.title3.bold())
            }
            HStack(spacing: 14) {
                timeItem("İmza", state.signOn)
                timeItem("TOBT", state.tobt)
                timeItem("TSAT", state.tsat)
                timeItem("CTOT", state.ctot)
                Spacer()
                Link(destination: URL(string: "ucus://refresh")!) {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .padding(8)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if stale {
                Text("Süre doldu").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .foregroundStyle(.white)
    }

    private func timeItem(_ title: String, _ date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
            if let date {
                Text(date, format: .dateTime.hour().minute()).font(.subheadline.bold().monospacedDigit())
            } else {
                Text("—").font(.subheadline)
            }
        }
    }
}

/// "✈︎ Geliş AYT · park 13:42" ya da "✈︎ Geliş AYT · parkta ~19:51"
struct InboundLine: View {
    let info: InboundInfo

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "airplane.arrival")
            Text("Geliş").foregroundStyle(.white.opacity(0.6))
            Text(info.fromCode.isEmpty ? "—" : info.fromCode).bold()
            Text("·")
            if let parked = info.parked {
                Text("park")
                Text(parked, format: .dateTime.hour().minute()).bold()
            } else if let est = info.estimatedPark {
                Text(info.landed != nil ? "indi, parkta ~" : "parkta ~")
                Text(est, format: .dateTime.hour().minute()).bold()
            } else {
                Text("bilgi yok")
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
