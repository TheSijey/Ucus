import SwiftUI

/// Gün gün tüm kayıtlar; düzeltme, silme ve elle ekleme.
struct HistoryView: View {
    @EnvironmentObject private var store: Store
    @State private var editor: EditorTarget?

    private struct DayGroup: Identifiable {
        let id: Date
        let items: [Entry]
    }

    private var groups: [DayGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.entries) { cal.startOfDay(for: $0.start) }
        return dict.keys.sorted(by: >).map { DayGroup(id: $0, items: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView("Henüz kayıt yok", systemImage: "calendar", description: Text("Kayıtlar eklendikçe burada gün gün listelenir."))
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.items) { entry in
                                    Button {
                                        editor = EditorTarget(entry: entry, isNew: false)
                                    } label: {
                                        EntryRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) {
                                        Button("Sil", role: .destructive) { store.delete(entry) }
                                    }
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Fmt.day(group.id))
                                        .font(.headline)
                                        .foregroundStyle(Theme.ink)
                                    Text(daySummary(group.id))
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                                .textCase(nil)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Geçmiş")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(EntryKind.allCases) { kind in
                            Button {
                                add(kind)
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label("Kayıt ekle", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editor) { target in
                EntryEditor(entry: target.entry, isNew: target.isNew)
            }
        }
    }

    private func daySummary(_ day: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let s = store.summary(from: day, to: min(end, Date()))
        var parts = ["\(s.feedCount) beslenme", "\(s.wet) ıslak, \(s.dirty) kirli bez"]
        if s.sleepSeconds > 0 { parts.append("uyku \(Fmt.duration(s.sleepSeconds))") }
        return parts.joined(separator: " · ")
    }

    private func add(_ kind: EntryKind) {
        var e = Entry(kind: kind, start: Date())
        switch kind {
        case .bottle:
            e.amountML = store.lastBottle?.amountML ?? 60
            e.bottleContent = store.lastBottle?.bottleContent ?? .formula
        case .diaper:
            e.diaper = .wet
        case .sleep:
            e.start = Date().addingTimeInterval(-3600)
            e.end = Date()
        default:
            break
        }
        editor = EditorTarget(entry: e, isNew: true)
    }
}
