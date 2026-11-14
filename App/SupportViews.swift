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

struct AddFlightView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Date, String) -> Void

    @State private var date = Date()
    @State private var flight = ""
    @State private var added: [String] = []
    @FocusState private var focused: Bool

    private var canAdd: Bool { !flight.trimmingCharacters(in: .whitespaces).isEmpty }

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
                    TextField(L("Sefer (1751 ya da TK1751)", "Flight (1751 or TK1751)"), text: $flight)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(addCurrent)
                } footer: {
                    Text(L("İstanbul kalkışlarında bilgiler İGA CDM'den, dış meydan kalkışlarında uçuş verisinden gelir. Ekledikçe takvim bir sonraki güne geçer.", "Istanbul departures use İGA CDM; outstation departures use flight data. The date moves to the next day after each add."))
                }
                if !added.isEmpty {
                    Section(L("Eklenenler", "Added")) {
                        ForEach(added, id: \.self) { Text($0) }
                    }
                }
            }
            // Klavye açıkken de hep görünen büyük Ekle butonu
            .safeAreaInset(edge: .bottom) {
                Button(action: addCurrent) {
                    Label(L("Ekle", "Add") + " · \(UTCFormat.shortDay(date))", systemImage: "plus.circle.fill")
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
            .navigationTitle(L("Uçuş ekle", "Add flight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Bitti", "Done")) { dismiss() }
                }
            }
        }
    }

    private func addCurrent() {
        let f = flight.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return }
        onAdd(date, f)
        added.insert("\(UTCFormat.shortDay(date)) – \(FlightStore.normalizeFlight(f))", at: 0)
        flight = ""
        date = UTC.calendar.date(byAdding: .day, value: 1, to: date) ?? date
        focused = true
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
