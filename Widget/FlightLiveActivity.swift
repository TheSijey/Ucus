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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 10)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("STAND").font(.caption2).foregroundStyle(.secondary)
                        Text(Display.text(s.stand)).font(.title2.bold()).foregroundStyle(.cyan)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, 10)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("SID \(Display.text(s.sid ?? ""))")
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
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
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
            Text("\(Display.text(state.registration)) · SID \(Display.text(state.sid ?? ""))")
                .font(.caption)
            PhaseCountdown(state: state)
                .font(.caption.bold())
        }
        .padding(12)
        .foregroundStyle(.white)
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 1) Sefer → varış            STAND C3
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.flight).font(.subheadline.bold())
                if !state.destination.isEmpty {
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(state.destination).font(.subheadline.bold())
                }
                Spacer(minLength: 4)
                Text("STAND").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(Display.text(state.stand)).font(.title3.bold()).foregroundStyle(.cyan)
            }
            // 2) Tescil tip               Gate
            HStack(alignment: .firstTextBaseline) {
                Text(Display.text(state.registration)).font(.subheadline.bold())
                Text(state.aircraftType).font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("SID \(Display.text(state.sid ?? ""))").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            // 3) Geliş
            if let ib = state.freshInbound {
                InboundLine(info: ib)
            }
            // 4) Sayaçlar                 RWY
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let leave = state.upcomingLeave() {
                    Image(systemName: "house.fill").font(.caption2).foregroundStyle(.green)
                    Countdown(target: leave)
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                        .frame(maxWidth: 70, alignment: .leading)
                }
                Text(L("İmzaya", "Sign-on")).font(.caption).foregroundStyle(.white.opacity(0.6))
                Countdown(target: state.signOn)
                    .font(.subheadline.bold())
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: 70, alignment: .leading)
                Spacer(minLength: 4)
                Text("RWY").font(.caption).foregroundStyle(.white.opacity(0.6))
                Text(Display.text(state.runway)).font(.subheadline.bold())
            }
            // 5) Saatler tek satır          ↻
            HStack(spacing: 8) {
                timeInline(L("İmza", "S/O"), state.signOn)
                timeInline("TOBT", state.tobt)
                timeInline("TSAT", state.tsat)
                timeInline("CTOT", state.ctot)
                Spacer(minLength: 2)
                Image(systemName: "arrow.clockwise")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if stale {
                Text(L("Süre doldu", "Expired")).font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .foregroundStyle(.white)
    }

    private func timeInline(_ title: String, _ date: Date?) -> some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(.white.opacity(0.55))
            if let date {
                Text(date, format: .dateTime.hour().minute()).bold()
            } else {
                Text("—")
            }
        }
        .font(.caption2.monospacedDigit())
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

/// "✈︎ Geliş AYT · park 13:42 · 47 dk önce" ya da "✈︎ Geliş AYT · parkta ~19:51"
struct InboundLine: View {
    let info: InboundInfo

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "airplane.arrival")
            Text(L("Geliş", "Inbound")).foregroundStyle(.white.opacity(0.6))
            Text(info.fromCode.isEmpty ? "—" : info.fromCode).bold()
            Text("·")
            if let parked = info.parked {
                Text("park\(info.approx)")
                Text(parked, format: .dateTime.hour().minute()).bold()
                Text("·")
                // iOS kendi işletir; sadece saat ve dakika (saniyesiz)
                Text(.currentDate, format: .offset(to: parked, allowedFields: [.hour, .minute], sign: .never))
                Text(L("önce", "ago"))
            } else if let est = info.estimatedPark {
                Text(info.landed != nil ? L("indi, parkta ~", "landed, on stand ~") : L("parkta ~", "on stand ~"))
                Text(est, format: .dateTime.hour().minute()).bold()
            } else {
                Text(L("bilgi yok", "no data"))
            }
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
