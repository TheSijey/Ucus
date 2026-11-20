import SwiftUI
import UIKit

// MARK: - Uçuş ekleme

enum UTCFormat {
    private static func style(_ base: Date.FormatStyle) -> Date.FormatStyle {
        var st = base
        st.timeZone = UTC.zone
        st.locale = Lang.locale
        return st
    }
    /// "10 Kasım Pazartesi"
    static func day(_ d: Date) -> String {
        d.formatted(style(.dateTime.day().month(.wide).weekday(.wide)))
    }
    /// "10 Kas"
    static func shortDay(_ d: Date) -> String {
        d.formatted(style(.dateTime.day().month(.abbreviated)))
    }
    /// "10 Kasım 22:30"
    static func dayTime(_ d: Date) -> String {
        d.formatted(style(.dateTime.day().month(.wide).hour().minute()))
    }
}

/// Uçuş ekle / düzenle: tek bacak ya da git-gel; dönüş otomatik önerilir, istenirse değiştirilir; + bacak ekle.
struct AddFlightView: View {
    @Environment(\.dismiss) private var dismiss
    var editing: PlannedFlight? = nil
    var onDelete: ((PlannedFlight) -> Void)? = nil
    let onSave: (PlannedFlight) -> Void

    struct Row: Identifiable, Equatable {
        var id = UUID()
        var flight = ""
        var nextDay = false
        var auto = false
    }

    @State private var date = Date()
    @State private var first = ""
    @State private var kind: TripKind = .turn
    @State private var rows: [Row] = []          // ilk bacaktan sonrakiler (git-gelde ilki dönüş)
    @State private var previews: [String: LegInfo] = [:]
    @State private var missing: Set<String> = []
    @State private var added: [String] = []
    @FocusState private var focused: Bool

    private var canAdd: Bool { !first.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L("Tarih", "Date"), selection: $date,
                               in: UTC.calendar.date(byAdding: .day, value: -1, to: UTC.startOfDay(Date()))!...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.timeZone, UTC.zone)
                        .environment(\.locale, Lang.locale)
                } header: {
                    Text(L("Tarih (UTC – roster'daki gibi)", "Date (UTC – as on your roster)"))
                }

                Section {
                    Picker("", selection: $kind) {
                        Text(L("Tek bacak", "One leg")).tag(TripKind.single)
                        Text(L("Git-gel", "Out and back")).tag(TripKind.turn)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, k in applyKind(k) }

                    legField(title: L("1. bacak", "Leg 1"), text: $first, nextDay: nil, autoBadge: false, previous: nil, focus: true)
                    // Satırlar kimlikle bağlanır: bir satır silinince (git-gel → tek bacak) eski sıra numarasına erişilip çökmesin
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        let id = row.id
                        legField(title: kind == .turn && i == 0 ? L("Dönüş", "Return") : L("\(i + 2). bacak", "Leg \(i + 2)"),
                                 text: rowBinding(id, \.flight, ""), nextDay: rowBinding(id, \.nextDay, false), autoBadge: row.auto,
                                 previous: i == 0 ? first : (rows.indices.contains(i - 1) ? rows[i - 1].flight : first),
                                 onDelete: kind == .turn && i == 0 ? nil : { rows.removeAll { $0.id == id } },
                                 onEdit: { if let j = rows.firstIndex(where: { $0.id == id }) { rows[j].auto = false } })
                    }
                    Button { rows.append(Row()) } label: {
                        Label(L("Bacak ekle", "Add leg"), systemImage: "plus.circle")
                    }
                } header: {
                    Text(L("Seferler", "Flights"))
                } footer: {
                    Text(L("Git-gel'de dönüş seferi otomatik önerilir; yanlışsa üstüne yazabilirsin. O gün daha fazla bacak varsa \"Bacak ekle\" ile ekle. Her seferin rotası ve saati altında görünür.",
                           "For out-and-back the return flight is suggested automatically; type over it if wrong. If you fly more legs that day, use \"Add leg\". Each flight's route and time appear below it."))
                }

                if let f = editing, let onDelete {
                    Section {
                        Button(L("Uçuşu sil", "Delete flight"), role: .destructive) {
                            onDelete(f)
                            dismiss()
                        }
                    } footer: {
                        Text(L("İptal olan ya da yanlış eklenen uçuşu listeden kaldırır.", "Removes a cancelled or wrongly added flight from the list."))
                    }
                }
                if !added.isEmpty {
                    Section(L("Eklenenler", "Added")) {
                        ForEach(added, id: \.self) { Text($0) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label(editing == nil ? L("Ekle", "Add") + " · \(UTCFormat.shortDay(date))" : L("Kaydet", "Save"),
                          systemImage: editing == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAdd)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle(editing == nil ? L("Uçuş ekle", "Add flight") : L("Uçuşu düzenle", "Edit flight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? L("Bitti", "Done") : L("Vazgeç", "Cancel")) { dismiss() }
                }
            }
            .onAppear(perform: loadEditing)
            .task(id: "\(first)|\(kind)|\(UTC.startOfDay(date).timeIntervalSince1970)") { await suggestReturn() }
        }
    }

    // MARK: Satır

    @ViewBuilder
    private func legField(title: String, text: Binding<String>, nextDay: Binding<Bool>?, autoBadge: Bool, previous: String?,
                          focus: Bool = false, onDelete: (() -> Void)? = nil, onEdit: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(title).font(.subheadline).foregroundStyle(Palette.secondary).frame(width: 62, alignment: .leading)
                TextField("TK1751", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; onEdit?() }))
                    .font(.title3.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .modifier(FocusIf(on: focus, binding: $focused))
                if autoBadge { AutoBadge() }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("Bacağı sil", "Delete leg"))
                }
            }
            if let nextDay {
                Toggle(L("Ertesi gün (UTC)", "Next day (UTC)"), isOn: nextDay).font(.caption)
            }
            let n = FlightStore.normalizeFlight(text.wrappedValue)
            let day = legDay(nextDay?.wrappedValue == true)
            if !n.isEmpty {
                if let p = previews[key(n, day)] {
                    let prevTo = previous.flatMap { prev in previews[key(FlightStore.normalizeFlight(prev), legDay(false))]?.toICAO ?? previews[key(FlightStore.normalizeFlight(prev), legDay(true))]?.toICAO }
                    let disconnected = prevTo != nil && !p.fromICAO.isEmpty && prevTo != p.fromICAO
                    Text("\(p.fromIATA.isEmpty ? p.fromICAO : p.fromIATA) → \(p.toIATA.isEmpty ? p.toICAO : p.toIATA) · \(FlightHelpers.utc(p.departure))" + (disconnected ? "" : " ✓"))
                        .font(.caption.bold()).foregroundStyle(disconnected ? Palette.warn : Palette.outbound)
                    if disconnected {
                        Text(L("Bu sefer önceki bacağın indiği meydandan kalkmıyor.", "This flight doesn't depart from where the previous leg lands."))
                            .font(.caption2).foregroundStyle(Palette.warn)
                    }
                } else if missing.contains(key(n, day)) {
                    Text(L("Bu gün için bulunamadı; numarayı ve tarihi kontrol et.", "Not found for this day; check the number and date."))
                        .font(.caption2).foregroundStyle(Palette.secondary)
                }
            }
        }
        .task(id: key(FlightStore.normalizeFlight(text.wrappedValue), legDay(nextDay?.wrappedValue == true))) {
            try? await Task.sleep(nanoseconds: 700_000_000)   // yazmayı bitirince sor
            await check(text.wrappedValue, nextDay: nextDay?.wrappedValue == true)
        }
    }

    // MARK: Mantık

    private func rowBinding<T>(_ id: UUID, _ kp: WritableKeyPath<Row, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { rows.first { $0.id == id }?[keyPath: kp] ?? fallback },
                set: { v in if let j = rows.firstIndex(where: { $0.id == id }) { rows[j][keyPath: kp] = v } })
    }

    private func key(_ n: String, _ day: Date) -> String { "\(n)|\(day.timeIntervalSince1970)" }
    private func legDay(_ next: Bool) -> Date {
        let d = UTC.startOfDay(date)
        return next ? UTC.calendar.date(byAdding: .day, value: 1, to: d) ?? d : d
    }

    private func check(_ raw: String, nextDay: Bool) async {
        let n = FlightStore.normalizeFlight(raw)
        guard n.range(of: #"^[A-Z0-9]{2}\d{1,4}[A-Z]?$"#, options: .regularExpression) != nil, InboundService.rapidKey != nil else { return }
        let day = legDay(nextDay)
        let k = key(n, day)
        guard previews[k] == nil, !missing.contains(k) else { return }
        if let p = await AeroDataBox.preview(flight: n, utcDay: day) { previews[k] = p } else { missing.insert(k) }
    }

    /// Git-gel: dönüşü sefer numarasının bir fazlası (olmazsa bir eksiği) olarak öner; kullanıcı yazdıysa dokunma.
    private func suggestReturn() async {
        guard kind == .turn else { return }
        if rows.isEmpty { rows = [Row(auto: true)] }
        guard rows[0].auto || rows[0].flight.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        let n = FlightStore.normalizeFlight(first)
        let letters = String(n.prefix { $0.isLetter })
        guard let num = Int(n.dropFirst(letters.count)) else { return }
        var pick = "\(letters)\(num + 1)"
        // Varış meydanı biliniyorsa önerinin oradan kalktığını doğrula; değilse bir eksiğini dene
        await check(first, nextDay: false)
        if let outTo = previews[key(n, legDay(false))]?.toICAO, InboundService.rapidKey != nil {
            await check(pick, nextDay: false)
            if previews[key(pick, legDay(false))]?.fromICAO != outTo {
                let alt = "\(letters)\(num - 1)"
                await check(alt, nextDay: false)
                if previews[key(alt, legDay(false))]?.fromICAO == outTo { pick = alt }
            }
        }
        guard kind == .turn, !rows.isEmpty, rows[0].auto || rows[0].flight.isEmpty else { return }
        rows[0].flight = pick
        rows[0].auto = true
    }

    private func applyKind(_ k: TripKind) {
        if k == .turn, rows.first?.auto != true, rows.first.map({ !$0.flight.isEmpty }) != true {
            if rows.isEmpty { rows = [Row(auto: true)] } else { rows[0].auto = true }
        }
        if k == .single, rows.first?.auto == true { rows.remove(at: 0) }
    }

    private func loadEditing() {
        guard let f = editing, first.isEmpty else {
            if editing == nil, rows.isEmpty, kind == .turn { rows = [Row(auto: true)] }
            return
        }
        date = f.date
        first = f.flight
        kind = f.kind ?? .turn
        rows = (f.legs ?? []).map { Row(id: $0.id, flight: $0.flight, nextDay: $0.dayOffset > 0) }
        if kind == .turn, rows.isEmpty { rows = [Row(auto: true)] }
    }

    private func save() {
        let f = first.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return }
        let legs = rows.filter { !$0.flight.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { PlannedLeg(id: $0.id, flight: $0.flight, dayOffset: $0.nextDay ? 1 : 0) }
        var p = editing ?? PlannedFlight(date: date, flight: f)
        p.date = date
        p.flight = f
        p.kind = kind
        p.legs = legs
        onSave(p)
        if editing != nil { dismiss(); return }
        added.insert("\(UTCFormat.shortDay(date)) – " + ([FlightStore.normalizeFlight(f)] + legs.map { FlightStore.normalizeFlight($0.flight) }).joined(separator: " · "), at: 0)
        first = ""
        rows = kind == .turn ? [Row(auto: true)] : []
        date = UTC.calendar.date(byAdding: .day, value: 1, to: date) ?? date
        focused = true
    }
}

private struct FocusIf: ViewModifier {
    let on: Bool
    var binding: FocusState<Bool>.Binding
    func body(content: Content) -> some View {
        if on { content.focused(binding) } else { content }
    }
}

// MARK: - Ayarlar

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.leaveMinutesKey) private var leaveMinutes = 60
    @AppStorage(Lang.key, store: SharedStore.defaults) private var language = "system"
    @AppStorage(AppSettings.hotelRemindKey) private var hotelRemind = 15

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Dil", "Language"), selection: $language) {
                        Text(L("Sistem", "System")).tag("system")
                        Text("Türkçe").tag("tr")
                        Text("English").tag("en")
                    }
                } footer: {
                    Text(L("Kilit ekranı ve widget bir sonraki yenilemede yeni dile geçer.", "The Lock Screen and widgets switch at the next refresh."))
                }
                Section {
                    Stepper(value: $leaveMinutes, in: 0...240, step: 5) {
                        LabeledContent(L("Evden çıkış", "Leave home")) {
                            Text(leaveMinutes == 0 ? L("Kapalı", "Off") : L("İmzadan \(Display.minutes(leaveMinutes)) önce", "\(Display.minutes(leaveMinutes)) before sign-on"))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text(L("Çıkış bildirimi", "Leave alert"))
                } footer: {
                    Text(L("Bu saate kadar Ada'da yeşil ev sayacı, sonra sarı imza sayacı görünür. O anda uçak sesli bildirim gelir. Değişiklik bir sonraki takip başlatmada geçerli olur.", "Until then the Dynamic Island shows a green leave-home countdown, then the yellow sign-on countdown. An alert with the chime sound arrives at that moment. Changes apply the next time you start tracking."))
                }
                HomeLocationSection(leaveMinutes: leaveMinutes)
                Section {
                    Stepper(value: $hotelRemind, in: 0...60, step: 5) {
                        LabeledContent(L("Otel hatırlatması", "Hotel reminder")) {
                            Text(hotelRemind == 0 ? L("Çıkış anında", "At pickup") : L("\(hotelRemind) dk önce", "\(hotelRemind) min before"))
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text(L("Dış meydan kalkışlarında, girdiğin otelden çıkış saatinden bu kadar önce uçak sesli hatırlatma gelir.", "For outstation departures, a chime reminder arrives this long before the hotel pickup time you enter."))
                }
                if let q = AeroDataBox.quota {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(L("Kalan", "Remaining")) {
                                Text("\(q.remaining.formatted()) / \(q.limit.formatted()) unit").monospacedDigit()
                                    .foregroundStyle(q.remaining < q.limit / 10 ? Palette.warn : .primary)
                            }
                            ProgressView(value: Double(q.remaining), total: Double(max(q.limit, 1)))
                                .tint(q.remaining < q.limit / 10 ? Palette.warn : Palette.stand)
                        }
                    } header: {
                        Text(L("Uçuş verisi (AeroDataBox)", "Flight data (AeroDataBox)"))
                    } footer: {
                        Text(L("Son kontrol \(q.at.formatted(.dateTime.day().month().hour().minute()))", "Checked \(q.at.formatted(.dateTime.day().month().hour().minute()))")
                             + (q.reset.map { L(" · yenilenme \($0.formatted(.dateTime.day().month(.abbreviated)))", " · resets \($0.formatted(.dateTime.day().month(.abbreviated)))") } ?? "")
                             + L(" · bir sorgu ~2 unit", " · one query ~2 units"))
                    }
                }
                Section {
                    NavigationLink(L("Nasıl kullanılır?", "How to use")) { HelpView() }
                    NavigationLink(L("Tanılama", "Diagnostics")) { DiagnosticsView() }
                }
                if InboundService.isEnabled {
                    Section {
                        let stats = TaxiStats.summary
                        if stats.isEmpty {
                            Text(L("Henüz ölçüm yok. Gelen uçağı parka girmiş uçuşlara baktıkça birikir.", "No samples yet. They build up as inbound aircraft reach the stand."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(stats, id: \.zone) { z in
                            LabeledContent(L("\(z.zone) standları", "\(z.zone) stands"), value: L("\(z.minutes) dk · \(z.count) ölçüm", "\(z.minutes) min · \(z.count) samples"))
                        }
                    } header: {
                        Text(L("Öğrenilen taksi süreleri", "Learned taxi times"))
                    }
                }
                Section {
                    Button(L("Bildirim sesini dene", "Test alert sound")) {
                        Task { await NotificationManager.test() }
                    }
                } footer: {
                    Text(L("3 saniye sonra deneme bildirimi gelir. Telefon sessizdeyse ses çalmaz.", "A test alert arrives in 3 seconds. No sound if the phone is on silent."))
                }
            }
            .navigationTitle(L("Ayarlar", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Bitti", "Done")) { dismiss() }
                }
            }
        }
    }
}

struct DiagnosticsView: View {
    @State private var lines = DebugLog.lines

    var body: some View {
        List {
            Section {
                if lines.isEmpty { Text(L("Kayıt yok.", "No entries.")).foregroundStyle(.secondary) }
                ForEach(lines, id: \.self) { Text($0).font(.caption.monospaced()) }
            } footer: {
                Text(L("Takip kendiliğinden kapanma gibi bir sorun olursa bu ekranın görüntüsünü gönder.", "If tracking stops by itself, send a screenshot of this screen."))
            }
            Section {
                Button(L("Kayıtları temizle", "Clear log"), role: .destructive) {
                    DebugLog.clear()
                    lines = []
                }
            }
        }
        .navigationTitle(L("Tanılama", "Diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { lines = DebugLog.lines }
    }
}

/// Flightradar24'ü mümkünse doğrudan uygulamasında açar.
enum FR24 {
    @MainActor
    static func open(_ url: URL, flight: String?) {
        let app = UIApplication.shared
        // 1) Sadece uygulamada aç (iOS bu adresi FR24'e yönlendirebiliyorsa)
        app.open(url, options: [.universalLinksOnly: true]) { ok in
            guard !ok else { return }
            // 2) FR24 uygulamasının kendi adresi
            let q = (flight ?? "").replacingOccurrences(of: " ", with: "")
            let scheme = URL(string: q.isEmpty ? "fr24://" : "fr24://\(q)")!
            app.open(scheme, options: [:]) { ok2 in
                guard !ok2 else { return }
                // 3) Safari
                app.open(url)
            }
        }
    }
}
