import SwiftUI

/// Dış meydan: otelden çıkış, imza ya da stand girişi. Saatler kalkış meydanının yerel saatiyle girilir.
struct ManualEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let state: FlightAttributes.ContentState
    let field: TodayView.ManualField

    @State private var date = Date()
    @State private var stand = ""
    @State private var saving = false

    private var entry: ManualTimes.Entry { ManualTimes.entry(for: state) }
    private var city: String { state.originCity ?? state.originCode }

    private var title: String {
        switch field {
        case .pickup: L("Otelden çıkış", "Hotel pickup")
        case .signOn: L("İmza saati", "Sign-on time")
        case .stand: "Stand"
        }
    }

    private var hasValue: Bool {
        switch field {
        case .pickup: entry.pickup != nil
        case .signOn: entry.signOn != nil
        case .stand: !(entry.stand ?? "").isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if field == .stand {
                    Section {
                        TextField(L("Stand (ör. 12)", "Stand (e.g. 12)"), text: $stand)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } footer: {
                        Text(L("Kilit ekranında ve Ada'da görünür.", "Shown on the Lock Screen and Dynamic Island."))
                    }
                } else {
                    Section {
                        DatePicker(title, selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .environment(\.timeZone, state.originTimeZone)
                            .environment(\.locale, Lang.locale)
                    } footer: {
                        Text(L("\(city) yerel saati. UTC: \(FlightHelpers.utc(date)) · Kalkış \(state.eobt.map { FlightHelpers.local($0, state.originTimeZone) } ?? "—") yerel",
                               "\(city) local time. UTC: \(FlightHelpers.utc(date)) · Departure \(state.eobt.map { FlightHelpers.local($0, state.originTimeZone) } ?? "—") local"))
                    }
                    if field == .pickup {
                        Section {
                            Text(L("Çıkıştan \(Display.minutes(AppSettings.hotelRemindMinutes)) önce uçak sesli hatırlatma gelir; süreyi Ayarlar'dan değiştirebilirsin.",
                                   "An airplane-chime reminder arrives \(Display.minutes(AppSettings.hotelRemindMinutes)) before pickup; change it in Settings."))
                                .font(.footnote).foregroundStyle(Palette.secondary)
                        }
                    }
                }
                if hasValue {
                    Section {
                        Button(L("Sil", "Clear"), role: .destructive) { save(clear: true) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Vazgeç", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(L("Kaydet", "Save")) { save(clear: false) }.bold()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            switch field {
            case .pickup: date = entry.pickup ?? state.signOn.addingTimeInterval(-30 * 60)
            case .signOn: date = entry.signOn ?? state.signOn
            case .stand: stand = entry.stand ?? state.stand
            }
        }
    }

    private func save(clear: Bool) {
        var e = entry
        switch field {
        case .pickup: e.pickup = clear ? nil : date
        case .signOn: e.signOn = clear ? nil : date
        case .stand:
            let v = stand.trimmingCharacters(in: .whitespaces).uppercased()
            e.stand = clear || v.isEmpty ? nil : v
        }
        saving = true
        Task {
            await model.saveManual(e)
            saving = false
            dismiss()
        }
    }
}
