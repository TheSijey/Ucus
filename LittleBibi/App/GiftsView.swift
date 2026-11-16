import SwiftUI

/// Takı defteri: kim ne getirdi, teşekkür edildi mi.
struct GiftsView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Gift?
    @State private var isNew = false
    @State private var filter: GiftKind?

    private struct DayGroup: Identifiable {
        let id: Date
        let items: [Gift]
    }

    var body: some View {
        let all = store.gifts
        let shown = all.filter { filter == nil || $0.kind == filter }
        let cal = Calendar.current
        let dict = Dictionary(grouping: shown) { cal.startOfDay(for: $0.date) }
        let groups = dict.keys.sorted(by: >).map { DayGroup(id: $0, items: dict[$0] ?? []) }

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        stat("Altın", all.filter { $0.kind == .gold }.reduce(0) { $0 + $1.count })
                        stat("Para", all.filter { $0.kind == .money }.count)
                        stat("Hediye", all.filter { $0.kind == .present }.count)
                        stat("Teşekkür bekliyor", all.filter { !$0.thanked }.count)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    Picker("Göster", selection: $filter) {
                        Text("Tümü").tag(GiftKind?.none)
                        ForEach(GiftKind.allCases) { Text($0.title).tag(GiftKind?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                if all.isEmpty {
                    Section {
                        Text("Hastanede ve ziyaretlerde gelen altın, para ve hediyeleri buraya not edin. Kimin ne getirdiği ve kime teşekkür edildiği kaybolmaz.")
                            .foregroundStyle(Theme.muted)
                    }
                }
                ForEach(groups) { group in
                    Section(Fmt.day(group.id)) {
                        ForEach(group.items) { gift in
                            row(gift)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Takı defteri")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isNew = true
                        editing = Gift(kind: filter ?? .gold)
                    } label: {
                        Label("Ekle", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { gift in
                GiftEditor(gift: gift, isNew: isNew)
            }
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func row(_ gift: Gift) -> some View {
        HStack(spacing: 12) {
            Button {
                isNew = false
                editing = gift
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: gift.kind.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.feedInk)
                        .frame(width: 40, height: 40)
                        .background(Theme.feed, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gift.giver.isEmpty ? "İsimsiz" : gift.giver)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(gift.summary)\(gift.relation.isEmpty ? "" : " · \(gift.relation)")")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                        if !gift.note.isEmpty {
                            Text(gift.note)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                var g = gift
                g.thanked.toggle()
                store.save(g)
            } label: {
                Text(gift.thanked ? "Teşekkür edildi" : "Teşekkür et")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(gift.thanked ? Theme.burpInk : Theme.onPrimary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
                    .background(gift.thanked ? Theme.burp : Theme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing) {
            Button("Sil", role: .destructive) { store.remove(gift) }
        }
    }
}

private struct GiftEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var gift: Gift
    let isNew: Bool

    private let goldTypes = ["Gram altın", "Çeyrek altın", "Yarım altın", "Tam altın", "Cumhuriyet altını", "Bilezik"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Kimden") {
                    TextField("Ad (ör. Ayşe Teyze)", text: $gift.giver)
                    TextField("Yakınlık (isteğe bağlı, ör. komşu)", text: $gift.relation)
                }
                Section("Ne getirdi") {
                    Picker("Tür", selection: $gift.kind) {
                        ForEach(GiftKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch gift.kind {
                    case .gold:
                        Picker("Altın türü", selection: $gift.what) {
                            Text("Seçin").tag("")
                            ForEach(goldTypes, id: \.self) { Text($0).tag($0) }
                        }
                        Stepper("Adet: \(gift.count)", value: $gift.count, in: 1...50)
                    case .money:
                        TextField("Tutar ya da not (ör. zarf)", text: $gift.what)
                    case .present:
                        TextField("Hediye (ör. battaniye)", text: $gift.what)
                    }
                }
                Section {
                    DatePicker("Tarih", selection: $gift.date, in: ...Date(), displayedComponents: .date)
                    Toggle("Teşekkür edildi", isOn: $gift.thanked)
                    TextField("Not (isteğe bağlı)", text: $gift.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if !isNew {
                    Section {
                        Button("Kaydı sil", role: .destructive) {
                            store.remove(gift)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Takı ekle" : "Takı")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: gift.kind) { _, new in
                if new != .gold {
                    gift.count = 1
                    if goldTypes.contains(gift.what) { gift.what = "" }
                } else if !goldTypes.contains(gift.what) {
                    gift.what = ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        var g = gift
                        g.giver = g.giver.trimmingCharacters(in: .whitespaces)
                        g.relation = g.relation.trimmingCharacters(in: .whitespaces)
                        g.what = g.what.trimmingCharacters(in: .whitespaces)
                        g.note = g.note.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.save(g)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(gift.giver.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
