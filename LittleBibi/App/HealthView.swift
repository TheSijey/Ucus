import Charts
import SwiftUI

/// Sağlık sekmesi: kontrol ve aşı takvimi, doktora sorulacaklar, gelişim.
struct HealthView: View {
    enum Page: String, CaseIterable, Identifiable {
        case schedule = "Takvim"
        case questions = "Sorular"
        case growth = "Gelişim"
        var id: String { rawValue }
    }

    @State private var page: Page = .schedule

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Bölüm", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch page {
                case .schedule: ScheduleList()
                case .questions: QuestionList()
                case .growth: GrowthList()
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Sağlık")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: Takvim

private struct ScheduleList: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        if let birth = store.profile.birthDate {
            let now = Date()
            let rows = Schedule.items.map { (item: $0, due: $0.due(birth: birth)) }
            let open = rows.filter { !store.isDone($0.item.key) }
            let done = rows.filter { store.isDone($0.item.key) }
            List {
                Section {
                    vitaminRow
                } header: {
                    Text("Her gün")
                }
                Section {
                    ForEach(open, id: \.item.key) { row in
                        scheduleRow(row.item, due: row.due, done: false, now: now)
                    }
                } header: {
                    Text("Sıradaki kontroller ve aşılar")
                } footer: {
                    Text("Sağlık Bakanlığı'nın bebek izlem ve aşı takvimine göre hazırlanmıştır. Kesin tarihleri ve aşıları aile hekiminiz belirler.")
                }
                if !done.isEmpty {
                    Section("Tamamlananlar") {
                        ForEach(done, id: \.item.key) { row in
                            scheduleRow(row.item, due: row.due, done: true, now: now)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView("Takvim doğumla başlar", systemImage: "calendar.badge.clock",
                                   description: Text("Ayarlar'da \"Bebek doğdu\"yu açıp doğum tarihini girdiğinizde kontrol ve aşı takvimi burada oluşur."))
        }
    }

    private var vitaminRow: some View {
        let mark = store.vitaminMark(on: Date())
        return Button {
            store.setVitamin(given: mark == nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mark == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(mark == nil ? Theme.muted : Theme.burpInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text("D vitamini")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(mark.map { "Bugün verildi · \(Fmt.time($0.givenAt))\($0.author.isEmpty ? "" : " · \($0.author)")" } ?? "Bugün henüz işaretlenmedi")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(mark == nil ? "Verildi olarak işaretle" : "İşareti kaldır")
    }

    private func scheduleRow(_ item: ScheduleItem, due: Date, done: Bool, now: Date) -> some View {
        Button {
            store.setDone(item.key, !done)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Theme.burpInk : Theme.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(item.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Text(done ? Fmt.date(due) : "\(Fmt.date(due)) · \(Fmt.relativeDay(due, now: now))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(!done && due < Calendar.current.startOfDay(for: now) ? Theme.noteInk : Theme.sleepInk)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(done ? "Yapılmadı olarak işaretle" : "Yapıldı olarak işaretle")
    }
}

// MARK: Doktora sorulacaklar

private struct QuestionList: View {
    @EnvironmentObject private var store: Store
    @State private var draft = ""
    @State private var editing: Question?
    @FocusState private var focused: Bool

    var body: some View {
        let open = store.questions.filter { !$0.answered }
        let answered = store.questions.filter { $0.answered }
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Aklınıza gelen soruyu yazın", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                    Button {
                        add()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Soruyu ekle")
                }
            } footer: {
                if let next = store.nextScheduleItem() {
                    Text("Sıradaki: \(next.item.title), \(Fmt.date(next.due)). Sorular o güne hazır olur.")
                }
            }
            Section("Sorulacaklar (\(open.count))") {
                if open.isEmpty {
                    Text("Bekleyen soru yok.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(open) { q in
                    questionRow(q)
                }
            }
            if !answered.isEmpty {
                Section("Cevaplananlar") {
                    ForEach(answered) { q in
                        questionRow(q)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(item: $editing) { q in
            QuestionEditor(question: q)
        }
    }

    private func questionRow(_ q: Question) -> some View {
        Button {
            editing = q
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(q.text)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if q.answered, !q.answer.isEmpty {
                    Text(q.answer)
                        .font(.subheadline)
                        .foregroundStyle(Theme.burpInk)
                        .multilineTextAlignment(.leading)
                }
                Text("\(q.author.isEmpty ? "" : q.author + " · ")\(Fmt.date(q.created))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Sil", role: .destructive) { store.remove(q) }
        }
        .swipeActions(edge: .leading) {
            Button(q.answered ? "Soruldu değil" : "Soruldu") {
                var x = q
                x.answered.toggle()
                x.answeredAt = x.answered ? Date() : nil
                store.save(x)
            }
            .tint(Theme.primary)
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.save(Question(text: text))
        draft = ""
    }
}

private struct QuestionEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var question: Question

    var body: some View {
        NavigationStack {
            Form {
                Section("Soru") {
                    TextField("Soru", text: $question.text, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Toggle("Doktora soruldu", isOn: $question.answered)
                    TextField("Doktorun cevabı", text: $question.answer, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Cevap")
                } footer: {
                    Text("Muayenede cevabı buraya not edin; sonra aynı soru aklınıza gelirse buradan bakarsınız.")
                }
                Section {
                    Button("Soruyu sil", role: .destructive) {
                        store.remove(question)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Soru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        var q = question
                        q.text = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        q.answer = q.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !q.answer.isEmpty { q.answered = true }
                        q.answeredAt = q.answered ? (q.answeredAt ?? Date()) : nil
                        store.save(q)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: Gelişim

private struct GrowthList: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Measurement?
    @State private var isNew = false

    var body: some View {
        let items = store.measurements
        let weights = items.filter { $0.weightGrams != nil }.sorted { $0.date < $1.date }
        List {
            Section {
                HStack(spacing: 10) {
                    latest("Kilo", items.first { $0.weightGrams != nil }.flatMap { $0.weightGrams }.map { Fmt.kg($0) })
                    latest("Boy", items.first { $0.heightCm != nil }.flatMap { $0.heightCm }.map { "\(Fmt.decimal($0)) cm" })
                    latest("Baş çevresi", items.first { $0.headCm != nil }.flatMap { $0.headCm }.map { "\(Fmt.decimal($0)) cm" })
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if weights.count >= 2 {
                Section("Kilo eğrisi") {
                    Chart(weights) { m in
                        LineMark(x: .value("Tarih", m.date), y: .value("Kilo (kg)", Double(m.weightGrams ?? 0) / 1000))
                            .foregroundStyle(Theme.primary)
                        PointMark(x: .value("Tarih", m.date), y: .value("Kilo (kg)", Double(m.weightGrams ?? 0) / 1000))
                            .foregroundStyle(Theme.primary)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Kilo ölçümlerinin zamana göre grafiği")
                }
            }
            Section {
                if items.isEmpty {
                    Text("Henüz ölçüm yok. Kontrollerde ölçülen kilo, boy ve baş çevresini buraya ekleyin.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(items) { m in
                    Button {
                        isNew = false
                        editing = m
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.summary.isEmpty ? "Ölçüm" : m.summary)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("\(Fmt.date(m.date))\(m.note.isEmpty ? "" : " · \(m.note)")")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Sil", role: .destructive) { store.remove(m) }
                    }
                }
            } header: {
                Text("Ölçümler")
            } footer: {
                Text("Grafik yalnızca girdiğiniz ölçümleri gösterir; değerlendirmeyi doktorunuz yapar.")
            }
            Section {
                Button {
                    isNew = true
                    editing = Measurement()
                } label: {
                    Label("Yeni ölçüm ekle", systemImage: "plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(item: $editing) { m in
            MeasurementEditor(measurement: m, isNew: isNew)
        }
    }

    private func latest(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            Text(value ?? "—")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct MeasurementEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    private let original: Measurement
    private let isNew: Bool
    @State private var date: Date
    @State private var weight: String
    @State private var height: String
    @State private var head: String
    @State private var note: String

    init(measurement: Measurement, isNew: Bool) {
        original = measurement
        self.isNew = isNew
        _date = State(initialValue: measurement.date)
        _weight = State(initialValue: measurement.weightGrams.map { String(format: "%.2f", Double($0) / 1000).replacingOccurrences(of: ".", with: ",") } ?? "")
        _height = State(initialValue: measurement.heightCm.map { Fmt.decimal($0) } ?? "")
        _head = State(initialValue: measurement.headCm.map { Fmt.decimal($0) } ?? "")
        _note = State(initialValue: measurement.note)
    }

    private var valid: Bool {
        Fmt.parse(weight) != nil || Fmt.parse(height) != nil || Fmt.parse(head) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Tarih", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    field("Kilo (kg)", text: $weight, hint: "ör. 3,45")
                    field("Boy (cm)", text: $height, hint: "ör. 51")
                    field("Baş çevresi (cm)", text: $head, hint: "ör. 35")
                } footer: {
                    Text("Bildiğiniz değerleri girmeniz yeterli; boş bırakılanlar kaydedilmez.")
                }
                Section("Not (isteğe bağlı)") {
                    TextField("ör. Aile hekimi, hastane, evde", text: $note)
                }
                if !isNew {
                    Section {
                        Button("Ölçümü sil", role: .destructive) {
                            store.remove(original)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Ölçüm ekle" : "Ölçüm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        var m = original
                        m.date = date
                        m.weightGrams = Fmt.parse(weight).map { Int(($0 * 1000).rounded()) }
                        m.heightCm = Fmt.parse(height)
                        m.headCm = Fmt.parse(head)
                        m.note = note.trimmingCharacters(in: .whitespaces)
                        store.save(m)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(!valid)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, hint: String) -> some View {
        LabeledContent(label) {
            TextField(hint, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}
