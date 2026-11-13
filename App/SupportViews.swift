import SwiftUI
import UIKit

// MARK: - Uçuş ekleme

enum UTCFormat {
    private static func style(_ base: Date.FormatStyle) -> Date.FormatStyle {
        var st = base
        st.timeZone = UTC.zone
        st.locale = Locale(identifier: "tr_TR")
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
                    DatePicker("Tarih", selection: $date,
                               in: UTC.calendar.date(byAdding: .day, value: -1, to: UTC.startOfDay(Date()))!...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.timeZone, UTC.zone)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                } header: {
                    Text("Tarih (UTC – roster'daki gibi)")
                }
                Section {
                    TextField("Sefer (1751 ya da TK1751)", text: $flight)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(addCurrent)
                } footer: {
                    Text("Ekledikçe takvim bir sonraki güne geçer; birden fazla uçuşu arka arkaya girebilirsin.")
                }
                if !added.isEmpty {
                    Section("Eklenenler") {
                        ForEach(added, id: \.self) { Text($0) }
                    }
                }
            }
            // Klavye açıkken de hep görünen büyük Ekle butonu
            .safeAreaInset(edge: .bottom) {
                Button(action: addCurrent) {
                    Label("Ekle · \(UTCFormat.shortDay(date))", systemImage: "plus.circle.fill")
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
            .navigationTitle("Uçuş ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $leaveMinutes, in: 0...240, step: 5) {
                        LabeledContent("Evden çıkış") {
                            Text(leaveMinutes == 0 ? "Kapalı" : "İmzadan \(Display.minutes(leaveMinutes)) önce")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Çıkış bildirimi")
                } footer: {
                    Text("Bu saate kadar Ada'da yeşil ev sayacı, sonra sarı imza sayacı görünür. O anda chime sesiyle bildirim gelir. Değişiklik bir sonraki takip başlatmada geçerli olur.")
                }
                Section {
                    NavigationLink("Nasıl kullanılır?") { HelpView() }
                    NavigationLink("Tanılama") { DiagnosticsView() }
                }
                if InboundService.isEnabled {
                    Section {
                        let stats = TaxiStats.summary
                        if stats.isEmpty {
                            Text("Henüz ölçüm yok. Gelen uçağı parka girmiş uçuşlara baktıkça birikir.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(stats, id: \.zone) { z in
                            LabeledContent("\(z.zone) standları", value: "\(z.minutes) dk · \(z.count) ölçüm")
                        }
                    } header: {
                        Text("Öğrenilen taksi süreleri")
                    }
                }
                Section {
                    Button("Bildirim sesini dene") {
                        Task { await NotificationManager.test() }
                    }
                } footer: {
                    Text("3 saniye sonra deneme bildirimi gelir. Telefon sessizdeyse ses çalmaz.")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
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
                if lines.isEmpty { Text("Kayıt yok.").foregroundStyle(.secondary) }
                ForEach(lines, id: \.self) { Text($0).font(.caption.monospaced()) }
            } footer: {
                Text("Takip kendiliğinden kapanma gibi bir sorun olursa bu ekranın görüntüsünü gönder.")
            }
            Section {
                Button("Kayıtları temizle", role: .destructive) {
                    DebugLog.clear()
                    lines = []
                }
            }
        }
        .navigationTitle("Tanılama")
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
