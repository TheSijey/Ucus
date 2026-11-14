import SwiftUI

/// Her kayıt türü için ekleme ve düzeltme formu.
struct EntryEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    private let original: Entry
    private let isNew: Bool

    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var leftMin: Int
    @State private var rightMin: Int
    @State private var lastSide: Side
    @State private var amount: Int
    @State private var content: BottleContent
    @State private var diaper: DiaperType
    @State private var note: String
    @State private var confirmDelete = false

    init(entry: Entry, isNew: Bool) {
        original = entry
        self.isNew = isNew
        _start = State(initialValue: entry.start)
        _hasEnd = State(initialValue: entry.end != nil)
        _end = State(initialValue: entry.end ?? Date())
        _leftMin = State(initialValue: Int((Double(entry.leftSeconds) / 60).rounded()))
        _rightMin = State(initialValue: Int((Double(entry.rightSeconds) / 60).rounded()))
        _lastSide = State(initialValue: entry.lastSide ?? .left)
        _amount = State(initialValue: entry.amountML ?? 60)
        _content = State(initialValue: entry.bottleContent ?? .formula)
        _diaper = State(initialValue: entry.diaper ?? .wet)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                Section("Zaman") {
                    DatePicker(original.kind == .sleep ? "Uyudu" : "Saat", selection: $start, in: ...Date())
                    if original.kind == .sleep {
                        Toggle("Uyandı", isOn: $hasEnd)
                        if hasEnd {
                            DatePicker("Uyandı", selection: $end, in: start...Date())
                        }
                    }
                }
                if original.kind != .note {
                    Section("Not (isteğe bağlı)") {
                        TextField("Not", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                    }
                }
                if !isNew {
                    Section {
                        if !original.author.isEmpty {
                            LabeledContent("Kaydı giren", value: original.author)
                        }
                        Button("Kaydı sil", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "\(original.kind.title) ekle" : original.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Bu kayıt silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    store.delete(original)
                    dismiss()
                }
                Button("Vazgeç", role: .cancel) {}
            }
        }
        .presentationDetents(original.kind == .nursing || original.kind == .sleep ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private var kindSection: some View {
        switch original.kind {
        case .nursing:
            Section("Süre") {
                Stepper("Sol: \(leftMin) dk", value: $leftMin, in: 0...180)
                Stepper("Sağ: \(rightMin) dk", value: $rightMin, in: 0...180)
                if leftMin > 0 && rightMin > 0 {
                    Picker("Son emzirilen taraf", selection: $lastSide) {
                        ForEach(Side.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        case .bottle:
            Section("Miktar") {
                Stepper("\(amount) ml", value: $amount, in: 0...500, step: 10)
                Picker("İçerik", selection: $content) {
                    ForEach(BottleContent.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .diaper:
            Section("Bez") {
                Picker("Bez", selection: $diaper) {
                    ForEach(DiaperType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .note:
            Section("Not") {
                TextField("Aklınıza geleni yazın", text: $note, axis: .vertical)
                    .lineLimit(3...8)
            }
        case .sleep, .burp:
            EmptyView()
        }
    }

    private var canSave: Bool {
        switch original.kind {
        case .note: return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .nursing: return leftMin + rightMin > 0
        default: return true
        }
    }

    private func save() {
        var e = original
        e.start = start
        e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch original.kind {
        case .nursing:
            // Sayaçla tutulan saniyeleri, dakika değişmediyse koru.
            if leftMin != Int((Double(original.leftSeconds) / 60).rounded()) || isNew { e.leftSeconds = leftMin * 60 }
            if rightMin != Int((Double(original.rightSeconds) / 60).rounded()) || isNew { e.rightSeconds = rightMin * 60 }
            if leftMin > 0 && rightMin > 0 {
                e.lastSide = lastSide
            } else {
                e.lastSide = leftMin > 0 ? .left : .right
            }
            e.end = start.addingTimeInterval(Double(e.leftSeconds + e.rightSeconds))
        case .bottle:
            e.amountML = amount
            e.bottleContent = content
        case .diaper:
            e.diaper = diaper
        case .sleep:
            e.end = hasEnd ? max(end, start) : nil
        case .burp, .note:
            break
        }
        store.upsert(e)
        dismiss()
    }
}
