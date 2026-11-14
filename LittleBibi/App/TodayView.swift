import SwiftUI

/// Tek bir sheet(item:) ile açılan kayıt formları.
struct EditorTarget: Identifiable {
    let id = UUID()
    let entry: Entry
    let isNew: Bool
}

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @Binding var showNursing: Bool
    @State private var editor: EditorTarget?
    @State private var toast: String?
    @State private var toastID = 0

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let now = context.date
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(now: now)
                        if let n = store.nursing {
                            nursingBanner(n)
                        }
                        statusCard(now: now)
                        Text("Hızlı kayıt")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        quickGrid
                        handoverCard(now: now)
                        todayList(now: now)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .background(Theme.bg.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0x35274F), in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .sheet(item: $editor) { target in
                EntryEditor(entry: target.entry, isNew: target.isNew)
            }
        }
    }

    // MARK: Parçalar

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.day().month(.wide).weekday(.wide)))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Text(title(now: now))
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private func title(now: Date) -> String {
        let name = store.profile.babyName.isEmpty ? "Bebeğimiz" : store.profile.babyName
        if let birth = store.profile.birthDate {
            let age = Fmt.age(birth: birth, now: now)
            return age.isEmpty ? name : "\(name) · \(age)"
        }
        return name
    }

    private func nursingBanner(_ n: ActiveNursing) -> some View {
        Button {
            showNursing = true
        } label: {
            HStack {
                Image(systemName: "heart.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.isRunning ? "Emzirme devam ediyor" : "Emzirme duraklatıldı")
                        .font(.subheadline.weight(.bold))
                    Text("\(n.side?.title ?? "") meme · sayaca dönmek için dokunun")
                        .font(.footnote)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Theme.onPrimary)
            .padding(14)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusCard(now: Date) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Son beslenme")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                if let feed = store.lastFeed {
                    Text(Fmt.ago(feed.start, now: now))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("\(feed.kind.title) · \(feed.detail) · \(Fmt.time(feed.start))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    if let last = store.lastNursing, let side = last.lastSide {
                        Text("Son emzirilen taraf: \(side.title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.sleepInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.sleep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    Text("Henüz kayıt yok")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text("İlk kaydı aşağıdaki butonlardan ekleyebilirsiniz.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                HStack(spacing: 8) {
                    chip(store.lastDiaper.map { "Son bez · \(Fmt.ago($0.start, now: now))" } ?? "Bez kaydı yok")
                    chip(store.activeSleep.map { "Uyuyor · \(Fmt.duration(now.timeIntervalSince($0.start)))" } ?? "Uyanık")
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var quickGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            quickButton("Emzirme", symbol: "heart.fill", kind: .nursing) {
                showNursing = true
            }
            quickButton("Biberon", symbol: "waterbottle.fill", kind: .bottle) {
                var e = Entry(kind: .bottle, start: Date())
                e.amountML = store.lastBottle?.amountML ?? 60
                e.bottleContent = store.lastBottle?.bottleContent ?? .formula
                editor = EditorTarget(entry: e, isNew: true)
            }
            quickButton("Bez", symbol: "drop.fill", kind: .diaper) {
                var e = Entry(kind: .diaper, start: Date())
                e.diaper = .wet
                editor = EditorTarget(entry: e, isNew: true)
            }
            quickButton(store.activeSleep == nil ? "Uyudu" : "Uyandı", symbol: store.activeSleep == nil ? "moon.zzz.fill" : "sun.max.fill", kind: .sleep) {
                if store.activeSleep == nil {
                    store.startSleep()
                    show("Uyku başladı")
                } else {
                    store.endSleep()
                    show("Uyku kaydedildi")
                }
            }
            quickButton("Gaz çıktı", symbol: "wind", kind: .burp) {
                store.logBurp()
                show("Gaz kaydedildi")
            }
            quickButton("Not", symbol: "square.and.pencil", kind: .note) {
                editor = EditorTarget(entry: Entry(kind: .note, start: Date()), isNew: true)
            }
        }
    }

    private func quickButton(_ title: String, symbol: String, kind: EntryKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.tileInk(kind))
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.tile(kind), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func handoverCard(now: Date) -> some View {
        let s = store.summary(from: now.addingTimeInterval(-4 * 3600), to: now)
        let day = store.summary(from: Calendar.current.startOfDay(for: now), to: now)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nöbet devri")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("Son 4 saat")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    metric("\(s.feedCount) beslenme", feedDetail(s), kind: .nursing)
                    metric("\(s.diapers) bez", "\(s.wet) ıslak · \(s.dirty) kirli", kind: .diaper)
                    metric(s.sleepSeconds > 0 ? Fmt.duration(s.sleepSeconds) : "Uyku yok", "Uyku", kind: .sleep)
                    metric("\(s.burps) kez", "Gaz", kind: .burp)
                }
                Divider().overlay(Theme.line)
                Text("Bugün toplam: \(day.feedCount) beslenme · \(day.wet) ıslak, \(day.dirty) kirli bez · uyku \(day.sleepSeconds > 0 ? Fmt.duration(day.sleepSeconds) : "yok")")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func feedDetail(_ s: Summary) -> String {
        var parts: [String] = []
        if s.nursingCount > 0 { parts.append("Emzirme \(Fmt.duration(s.nursingSeconds))") }
        if s.bottleCount > 0 { parts.append("Biberon \(s.bottleML) ml") }
        return parts.isEmpty ? "Kayıt yok" : parts.joined(separator: " · ")
    }

    private func metric(_ value: String, _ label: String, kind: EntryKind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.tileInk(kind))
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.tileInk(kind))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Theme.tile(kind), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func todayList(now: Date) -> some View {
        let start = Calendar.current.startOfDay(for: now)
        let items = store.entries.filter { $0.start >= start }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Bugünün akışı")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if items.isEmpty {
                Text("Bugün henüz kayıt yok.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(items) { entry in
                    Button {
                        editor = EditorTarget(entry: entry, isNew: false)
                    } label: {
                        EntryRow(entry: entry)
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Düzenlemek için dokunun")
                }
            }
        }
    }

    private func show(_ message: String) {
        toastID += 1
        let id = toastID
        withAnimation { toast = message }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if id == toastID {
                withAnimation { toast = nil }
            }
        }
    }
}
