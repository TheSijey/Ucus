import SwiftUI
import WidgetKit

struct NextFlightEntry: TimelineEntry {
    let date: Date
    let active: SharedStore.Active?
    let planned: [SharedStore.Planned]
}

struct NextFlightProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(date: Date(),
                        active: .init(flight: "TK1751", registration: "TC-LTD", stand: "F13L", gate: "F13A",
                                      destination: "OSL", signOn: Date().addingTimeInterval(2700),
                                      leaveAt: nil, hideAt: Date().addingTimeInterval(4500)),
                        planned: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        let entry = current()
        if let a = entry.active, a.timeline != nil {
            // Zaman çizelgesindeki "şu an" işareti için 15 dk'da bir giriş
            let entries = (0..<32).map { i in
                NextFlightEntry(date: Date().addingTimeInterval(Double(i) * 900), active: a, planned: entry.planned)
            }.filter { $0.date < a.hideAt.addingTimeInterval(12 * 3600) }
            completion(Timeline(entries: entries, policy: .after(min(a.hideAt, Date().addingTimeInterval(8 * 3600)))))
            return
        }
        // Bir sonraki önemli anda (çıkış, kaybolma, UTC gün dönümü) ya da en geç 1 saatte yenile.
        var next = Date().addingTimeInterval(3600)
        if let a = entry.active {
            next = [a.leaveAt, a.hideAt, next].compactMap { $0 }.filter { $0 > Date() }.min() ?? next
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) {
            next = min(next, midnight.addingTimeInterval(60))
        }
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> NextFlightEntry {
        var active = SharedStore.active
        if let a = active, a.hideAt <= Date(), (a.timeline?.end ?? .distantPast) <= Date() { active = nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        let planned = SharedStore.planned.filter { $0.date >= today }
        return NextFlightEntry(date: Date(), active: active, planned: planned)
    }
}

struct NextFlightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextFlight", provider: NextFlightProvider()) { entry in
            NextFlightView(entry: entry)
                .widgetURL(URL(string: "ucus://open"))
        }
        .configurationDisplayName(L("Sıradaki uçuş", "Next flight"))
        .description(L("Takip edilen uçuşun standı ve imza sayacı ya da listendeki sıradaki uçuş.", "Stand and sign-on countdown of the tracked flight, or the next flight in your list."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextFlightView: View {
    let entry: NextFlightEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium {
                    LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.25), .black],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Kilit ekranı

    @ViewBuilder
    private var inline: some View {
        if let a = entry.active {
            Text("\(a.flight) · \(Display.text(a.stand)) · ") + Text(timerInterval: a.signOn.addingTimeInterval(-86_400)...a.signOn, countsDown: true)
        } else if let p = entry.planned.first {
            Text("\(p.flight) · \(dayText(p.date))")
        } else {
            Text(L("Uçuş yok", "No flight"))
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let a = entry.active {
            VStack(spacing: 0) {
                Image(systemName: "airplane").font(.caption2)
                Text(Display.text(a.stand)).font(.system(size: 13, weight: .bold)).minimumScaleFactor(0.6)
            }
        } else {
            Image(systemName: "airplane.departure")
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let a = entry.active {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(a.flight) · \(Display.text(a.stand))").font(.headline)
                Text(shortReg(a.registration)).font(.caption)
                HStack(spacing: 3) {
                    Text(a.leaveAt != nil ? L("Çıkışa", "Leave") : L("İmzaya", "Sign-on"))
                    Countdown(target: a.leaveAt ?? a.signOn)
                }
                .font(.caption.bold())
            }
        } else if let p = entry.planned.first {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Sıradaki uçuş", "Next flight")).font(.caption)
                Text(p.flight).font(.headline)
                Text(dayText(p.date)).font(.caption)
            }
        } else {
            Text(L("Uçuşlarım listesi boş", "My Flights list is empty")).font(.caption)
        }
    }

    // MARK: Ana ekran

    @ViewBuilder
    private var small: some View {
        if let a = entry.active {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(a.flight).font(.headline)
                    Spacer()
                    Text(a.destination).font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                }
                Text("STAND").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(Display.text(a.stand)).font(.system(size: 30, weight: .bold)).foregroundStyle(.cyan)
                    .minimumScaleFactor(0.6)
                Text(a.registration).font(.caption.bold())
                Spacer(minLength: 0)
                countdowns(a).font(.caption.bold())
            }
            .foregroundStyle(.white)
        } else {
            plannedList(limit: 2)
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let a = entry.active {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(a.flight) → \(a.destination)").font(.headline)
                    Text(a.registration).font(.subheadline.bold())
                    Text("Gate \(Display.text(a.gate))").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    countdowns(a).font(.subheadline.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("STAND").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Text(Display.text(a.stand)).font(.system(size: 40, weight: .bold)).foregroundStyle(.cyan)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    if let tl = a.timeline {
                        DayTimelineBar(data: tl, height: 6, compactLegend: true)
                            .frame(width: 170)
                    }
                }
            }
            .foregroundStyle(.white)
        } else {
            plannedList(limit: 4)
        }
    }

    private func countdowns(_ a: SharedStore.Active) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let leave = a.leaveAt, leave > Date() {
                HStack(spacing: 3) {
                    Image(systemName: "house.fill").font(.caption2)
                    Countdown(target: leave)
                }
                .foregroundStyle(.green)
            }
            HStack(spacing: 3) {
                Text(L("İmza", "Sign-on")).foregroundStyle(.white.opacity(0.6))
                Countdown(target: a.signOn)
            }
            .foregroundStyle(.yellow)
        }
    }

    private func plannedList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Sıradaki uçuşlar", "Upcoming flights")).font(.caption).foregroundStyle(.white.opacity(0.6))
            if entry.planned.isEmpty {
                Text(L("Liste boş", "List empty")).font(.subheadline)
            }
            ForEach(entry.planned.prefix(limit), id: \.self) { p in
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.flight).font(.headline)
                    Text(dayText(p.date)).font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortReg(_ r: String) -> String { r.isEmpty ? "—" : r }

    /// "Bugün" / "Yarın" / "14 Kas Cum" (UTC)
    private func dayText(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        if cal.isDateInToday(d) { return L("Bugün (UTC)", "Today (UTC)") }
        if cal.isDateInTomorrow(d) { return L("Yarın (UTC)", "Tomorrow (UTC)") }
        var st = Date.FormatStyle.dateTime.day().month(.abbreviated).weekday(.abbreviated)
        st.timeZone = TimeZone(identifier: "UTC")!
        st.locale = Lang.locale
        return d.formatted(st)
    }
}
