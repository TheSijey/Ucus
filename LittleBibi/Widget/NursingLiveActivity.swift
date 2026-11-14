import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LittleBibiWidgetBundle: WidgetBundle {
    var body: some Widget {
        NursingLiveActivity()
    }
}

private let lilac = Color(red: 0.80, green: 0.72, blue: 0.96)
private let peach = Color(red: 1.0, green: 0.80, blue: 0.70)
private let openURL = URL(string: "littlebibi://nursing")

struct NursingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NursingAttributes.self) { context in
            LockScreenView(state: context.state, babyName: context.attributes.babyName)
                .activityBackgroundTint(Color(red: 0.15, green: 0.11, blue: 0.23))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(openURL)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EMZİRME").font(.caption2).foregroundStyle(.secondary)
                        Text(s.sideTitle).font(.title2.bold()).foregroundStyle(lilac)
                    }
                    .padding(.leading, 8)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunningClock(state: s)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: 120, alignment: .trailing)
                        .padding(.trailing, 8)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(s.isPaused ? "Duraklatıldı" : "Devam ediyor")
                        Spacer()
                        if s.otherAccum > 0 {
                            Text("\(s.otherTitle) \(clockText(s.otherAccum))")
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Text(s.sideTitle).font(.caption.bold()).foregroundStyle(lilac)
            } compactTrailing: {
                RunningClock(state: s)
                    .font(.caption.bold())
                    .foregroundStyle(peach)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(lilac)
            }
            .widgetURL(openURL)
        }
    }
}

/// Çalışıyorsa kendi kendine ilerleyen, duraklatıldıysa sabit süre.
struct RunningClock: View {
    let state: NursingAttributes.ContentState

    var body: some View {
        if let origin = state.timerOrigin {
            Text(origin, style: .timer)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text(clockText(state.currentAccum))
                .monospacedDigit()
        }
    }
}

struct LockScreenView: View {
    let state: NursingAttributes.ContentState
    let babyName: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(babyName.isEmpty ? "Emzirme" : "\(babyName) · Emzirme")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(state.sideTitle) meme")
                    .font(.title2.bold())
                    .foregroundStyle(lilac)
                Group {
                    if state.isPaused {
                        Text("Duraklatıldı")
                    } else if state.otherAccum > 0 {
                        Text("\(state.otherTitle) \(clockText(state.otherAccum))")
                    } else {
                        Text("Devam ediyor")
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            RunningClock(state: state)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: 170, alignment: .trailing)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(16)
    }
}
