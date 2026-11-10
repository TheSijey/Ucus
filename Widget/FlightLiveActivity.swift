import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct UcusWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
    }
}

struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightAttributes.self) { context in
            LockScreenView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
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
                        Text("İmzaya").foregroundStyle(.secondary)
                        SignOnCountdown(signOn: s.signOn)
                            .frame(maxWidth: 70)
                            .foregroundStyle(.yellow)
                        Button(intent: RefreshFlightIntent()) {
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
                    SignOnCountdown(signOn: s.signOn)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: 52, alignment: .leading)
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
                Text(Display.text(state.gate)).bold().foregroundStyle(.cyan)
            }
            Text("\(Display.text(state.registration)) · Std \(Display.text(state.stand))")
                .font(.caption)
            HStack(spacing: 4) {
                Text("İmza").foregroundStyle(.white.opacity(0.6))
                SignOnCountdown(signOn: state.signOn).foregroundStyle(.yellow)
            }
            .font(.caption.bold())
        }
        .padding(8)
        .foregroundStyle(.white)
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.flight).font(.title2.bold())
                if !state.destination.isEmpty {
                    Image(systemName: "arrow.right").font(.caption)
                    Text(state.destination).font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("GATE").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Text(Display.text(state.gate)).font(.title.bold()).foregroundStyle(.cyan)
                }
            }
            HStack {
                Text(Display.text(state.registration)).font(.headline)
                Text(state.aircraftType).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("Stand \(Display.text(state.stand))").font(.headline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("İmzaya").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                SignOnCountdown(signOn: state.signOn)
                    .font(.title3.bold())
                    .foregroundStyle(.yellow)
                Spacer()
                Text("RWY").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                Text(Display.text(state.runway)).font(.title3.bold())
            }
            HStack(spacing: 14) {
                timeItem("İmza", state.signOn)
                timeItem("TOBT", state.tobt)
                timeItem("TSAT", state.tsat)
                timeItem("CTOT", state.ctot)
                Spacer()
                Button(intent: RefreshFlightIntent()) {
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
        .padding()
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
