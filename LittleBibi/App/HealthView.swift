import Charts
import PhotosUI
import SwiftUI
import UIKit

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
    @State private var exam = false

    var body: some View {
        let open = store.questions.filter { !$0.answered }
        let answered = store.questions.filter { $0.answered }
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Aklınıza gelen soruyu yazın", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
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
                Text("Fotoğraf ya da ilgili bir kayıt eklemek için soruya dokunun.")
            }
            if !open.isEmpty {
                Section {
                    Button {
                        exam = true
                    } label: {
                        Label("Muayene modunu aç", systemImage: "stethoscope")
                            .font(.headline)
                    }
                } footer: {
                    if let next = store.nextScheduleItem() {
                        Text("Sıradaki: \(next.item.title), \(Fmt.date(next.due)). Muayenede sorular tek tek gösterilir, cevabı yazıp geçersiniz.")
                    } else {
                        Text("Muayenede sorular tek tek gösterilir, cevabı yazıp geçersiniz.")
                    }
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
        .fullScreenCover(isPresented: $exam) {
            ExamModeView(questionIDs: open.map(\.id))
        }
    }

    private func questionRow(_ q: Question) -> some View {
        Button {
            editing = q
        } label: {
            VStack(alignment: .leading, spacing: 6) {
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
                QuestionExtras(question: q, thumbSize: 44)
                Text("\(q.author.isEmpty ? "" : q.author + " · ")\(Fmt.date(q.created))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Sil", role: .destructive) { store.removeWithPhotos(q) }
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

/// Bir sorunun fotoğrafları ve bağlı kaydı.
private struct QuestionExtras: View {
    @EnvironmentObject private var store: Store
    let question: Question
    let thumbSize: CGFloat

    var body: some View {
        let photos = question.photos.compactMap { store.photo($0) }
        let linked = question.linkedEntryID.flatMap { store.entry($0) }
        if !photos.isEmpty || linked != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !photos.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(photos) { p in
                            PhotoThumb(photo: p, size: thumbSize)
                        }
                    }
                }
                if let e = linked {
                    Label("\(Fmt.day(e.start)) \(Fmt.time(e.start)) · \(e.kind.title)\(e.detail.isEmpty ? "" : " · \(e.detail)")", systemImage: e.kind.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.tileInk(e.kind))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.tile(e.kind), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

struct PhotoThumb: View {
    let photo: Photo
    let size: CGFloat

    var body: some View {
        Group {
            if let data = Data(base64Encoded: photo.jpegBase64), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Fotoğraf")
    }
}

enum PhotoCompressor {
    /// Fotoğrafı en uzun kenarı 1280 piksel olacak şekilde küçültür ve 700 KB'ın altına sıkıştırır.
    static func base64(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1280
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.6, 0.45, 0.3, 0.2] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count < 520_000 {
                return jpeg.base64EncodedString()
            }
        }
        return nil
    }
}

private struct QuestionEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var question: Question
    @State private var picks: [PhotosPickerItem] = []
    @State private var newPhotos: [Photo] = []
    @State private var removed: Set<UUID> = []
    @State private var loading = false
    @State private var photoError: String?

    private var shownPhotos: [Photo] {
        question.photos.filter { !removed.contains($0) }.compactMap { store.photo($0) } + newPhotos
    }

    private var recentEntries: [Entry] {
        let since = Date().addingTimeInterval(-7 * 86400)
        return Array(store.entries.filter { $0.start >= since && $0.kind != .note }.prefix(40))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Soru") {
                    TextField("Soru", text: $question.text, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    if !shownPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(shownPhotos) { p in
                                    ZStack(alignment: .topTrailing) {
                                        PhotoThumb(photo: p, size: 84)
                                        Button {
                                            if newPhotos.contains(where: { $0.id == p.id }) {
                                                newPhotos.removeAll { $0.id == p.id }
                                            } else {
                                                removed.insert(p.id)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .accessibilityLabel("Fotoğrafı kaldır")
                                        .padding(4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if shownPhotos.count < 3 {
                        PhotosPicker(selection: $picks, maxSelectionCount: 3 - shownPhotos.count, matching: .images) {
                            Label(loading ? "Fotoğraf hazırlanıyor…" : "Fotoğraf ekle", systemImage: "photo.on.rectangle")
                        }
                        .disabled(loading)
                    }
                    if let photoError {
                        Text(photoError)
                            .font(.footnote)
                            .foregroundStyle(Theme.noteInk)
                    }
                } header: {
                    Text("Fotoğraf")
                } footer: {
                    Text("En fazla 3 fotoğraf. Küçültülerek kaydedilir ve eşinizle paylaşılır.")
                }
                Section {
                    Picker("Bağlı kayıt", selection: $question.linkedEntryID) {
                        Text("Yok").tag(UUID?.none)
                        if let id = question.linkedEntryID, !recentEntries.contains(where: { $0.id == id }), let e = store.entry(id) {
                            Text(label(e)).tag(UUID?.some(e.id))
                        }
                        ForEach(recentEntries) { e in
                            Text(label(e)).tag(UUID?.some(e.id))
                        }
                    }
                } header: {
                    Text("İlgili kayıt")
                } footer: {
                    Text("Örneğin uzun bir uyku ya da kirli bez kaydını soruya bağlayın; muayenede doktora gösterirsiniz.")
                }
                Section {
                    Toggle("Doktora soruldu", isOn: $question.answered)
                    TextField("Doktorun cevabı", text: $question.answer, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Cevap")
                }
                Section {
                    Button("Soruyu sil", role: .destructive) {
                        store.removeWithPhotos(question)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Soru")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                loading = true
                photoError = nil
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let b64 = PhotoCompressor.base64(from: data) {
                            newPhotos.append(Photo(jpegBase64: b64))
                        } else {
                            photoError = "Bir fotoğraf eklenemedi."
                        }
                    }
                    picks = []
                    loading = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .fontWeight(.bold)
                        .disabled(loading || question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func label(_ e: Entry) -> String {
        "\(Fmt.day(e.start)) \(Fmt.time(e.start)) · \(e.kind.title)\(e.detail.isEmpty ? "" : " · \(e.detail)")"
    }

    private func save() {
        for p in newPhotos { store.save(p) }
        for id in removed {
            if var p = store.photo(id) {
                p.deleted = true
                store.save(p)
            }
        }
        var q = question
        q.photoIDs = q.photos.filter { !removed.contains($0) } + newPhotos.map(\.id)
        if q.photoIDs?.isEmpty == true { q.photoIDs = nil }
        q.text = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
        q.answer = q.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.answer.isEmpty { q.answered = true }
        q.answeredAt = q.answered ? (q.answeredAt ?? Date()) : nil
        store.save(q)
        dismiss()
    }
}

/// Muayenede soruları tek tek gösterir; cevap yazılıp geçilir.
private struct ExamModeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let questionIDs: [UUID]
    @State private var index = 0
    @State private var answer = ""
    @State private var markedCheck = false

    private var current: Question? {
        guard index < questionIDs.count else { return nil }
        return store.questions.first { $0.id == questionIDs[index] }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let q = current {
                    Text("Soru \(index + 1) / \(questionIDs.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(q.text)
                                .font(.title2.bold())
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            QuestionExtras(question: q, thumbSize: 110)
                            if !q.author.isEmpty {
                                Text("Soran: \(q.author)")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    TextField("Doktorun cevabı (isteğe bağlı)", text: $answer, axis: .vertical)
                        .lineLimit(2...6)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    HStack(spacing: 10) {
                        Button("Atla") { next() }
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Button("Soruldu, sonraki") {
                            var x = q
                            x.answered = true
                            x.answeredAt = Date()
                            let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !a.isEmpty { x.answer = a }
                            store.save(x)
                            next()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                } else {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.burpInk)
                        .frame(maxWidth: .infinity)
                    Text("Sorular bitti")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                    if let next = store.nextScheduleItem() {
                        Button(markedCheck ? "\(next.item.title) yapıldı olarak işaretlendi" : "\(next.item.title) yapıldı olarak işaretle") {
                            store.setDone(next.item.key, true)
                            markedCheck = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(markedCheck)
                    }
                    Text("Ölçülen kilo, boy ve baş çevresini Gelişim bölümüne eklemeyi unutmayın.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Muayene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private func next() {
        answer = ""
        index += 1
        while index < questionIDs.count, current == nil { index += 1 }
    }
}

// MARK: Gelişim

private enum GrowthMetric: String, CaseIterable, Identifiable {
    case weight = "Kilo"
    case length = "Boy"
    case head = "Baş çevresi"
    var id: String { rawValue }

    var unit: String { self == .weight ? "kg" : "cm" }

    func value(_ m: Measurement) -> Double? {
        switch self {
        case .weight: return m.weightGrams.map { Double($0) / 1000 }
        case .length: return m.heightCm
        case .head: return m.headCm
        }
    }

    func table(_ sex: BabySex) -> [(Int, Double, Double, Double)] {
        switch (self, sex) {
        case (.weight, .girl): return WHOGrowth.weight_girl
        case (.weight, .boy): return WHOGrowth.weight_boy
        case (.length, .girl): return WHOGrowth.length_girl
        case (.length, .boy): return WHOGrowth.length_boy
        case (.head, .girl): return WHOGrowth.head_girl
        case (.head, .boy): return WHOGrowth.head_boy
        }
    }
}

private struct GrowthPoint: Identifiable {
    let id: UUID
    let x: Double
    let y: Double
}

private struct BandRow: Identifiable {
    let id: Int
    let low: Double
    let median: Double
    let high: Double
}

private struct GrowthList: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Measurement?
    @State private var isNew = false
    @State private var metric: GrowthMetric = .weight

    var body: some View {
        let items = store.measurements
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
            chartSection(items)
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

    @ViewBuilder
    private func chartSection(_ items: [Measurement]) -> some View {
        let birth = store.profile.birthDate
        let sex = store.profile.babySex
        let points: [GrowthPoint] = items.compactMap { m in
            guard let v = metric.value(m) else { return nil }
            if let birth {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: birth), to: Calendar.current.startOfDay(for: m.date)).day ?? 0
                guard days >= 0 else { return nil }
                return GrowthPoint(id: m.id, x: Double(days) / 30.4375, y: v)
            }
            return GrowthPoint(id: m.id, x: m.date.timeIntervalSinceReferenceDate / 86400 / 30.4375, y: v)
        }.sorted { $0.x < $1.x }
        let canBand = birth != nil && sex != nil
        let maxAge = min(24, max(6, Int((points.last?.x ?? 0).rounded(.up)) + 2))
        let band: [BandRow] = canBand ? metric.table(sex!).filter { $0.0 <= maxAge }.map { BandRow(id: $0.0, low: $0.1, median: $0.2, high: $0.3) } : []

        Section {
            Picker("Ölçü", selection: $metric) {
                ForEach(GrowthMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if points.isEmpty && band.isEmpty {
                Text("\(metric.rawValue) ölçümü girildiğinde grafik burada görünür.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            } else {
                Chart {
                    ForEach(band) { r in
                        AreaMark(x: .value("Ay", Double(r.id)), yStart: .value("Alt", r.low), yEnd: .value("Üst", r.high))
                            .foregroundStyle(Theme.sleep.opacity(0.7))
                    }
                    ForEach(band) { r in
                        LineMark(x: .value("Ay", Double(r.id)), y: .value("Ortanca", r.median), series: .value("Seri", "DSÖ ortanca"))
                            .foregroundStyle(Theme.muted)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Ay", p.x), y: .value(metric.rawValue, p.y), series: .value("Seri", "Bebek"))
                            .foregroundStyle(Theme.primary)
                        PointMark(x: .value("Ay", p.x), y: .value(metric.rawValue, p.y))
                            .foregroundStyle(Theme.primary)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel(canBand ? "Ay" : "")
                .chartYAxisLabel(metric.unit)
                .chartXAxis(canBand ? .automatic : .hidden)
                .frame(height: 220)
                .padding(.vertical, 6)
                .accessibilityLabel("\(metric.rawValue) ölçümlerinin grafiği")
            }
        } header: {
            Text("Grafik")
        } footer: {
            if canBand {
                Text("Mor alan, DSÖ büyüme standartlarına göre bebeklerin büyük çoğunluğunun bulunduğu aralık (−2 ile +2 standart sapma); kesik çizgi ortanca. Grafik bilgi amaçlıdır, değerlendirmeyi doktorunuz yapar.")
            } else {
                Text("DSÖ referans aralığını görmek için Ayarlar'da doğum tarihini ve cinsiyeti girin. Değerlendirmeyi doktorunuz yapar.")
            }
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
