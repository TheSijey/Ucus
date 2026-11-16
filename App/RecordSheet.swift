import SwiftUI

/// Kayıt ekranını açma isteği (önceden doldurulmuş alanlarla).
struct RecordRequest: Identifiable {
    let id = UUID()
    var record: FlightRecord
    var autoFields: Set<String> = []   // otomatik doldurulan alanlar ("runway", "stand", "procedure")
    var finish = false                 // "Uçuşu bitir" akışı: kaydet ya da atla, ikisinde de uçuş kapanır

    @MainActor init(icao: String, phase: FlightRecord.Phase, flight: FlightAttributes.ContentState? = nil) {
        record = FlightRecord(icao: icao, phase: phase)
        if let s = flight ?? FlightSession.shared.recent {
            record.flight = s.flight
            record.aircraftType = s.aircraftType
        }
    }

    /// Takip edilen uçuş için: varıştan sonra varış kaydı, öncesinde kalkış kaydı.
    @MainActor static func forCurrent(_ s: FlightAttributes.ContentState) -> RecordRequest {
        let returned = s.turn?.returnArrival.map { Date() > $0 } ?? false
        if returned {
            var r = RecordRequest(icao: s.origin ?? "LTFM", phase: .arrival, flight: s)
            if let rf = s.turn?.returnFlight { r.record.flight = rf }
            return r
        }
        let landed = s.turn?.outboundArrival.map { Date() > $0 } ?? false
        if landed, let dest = FlightHelpers.destICAO(s) {
            var r = RecordRequest(icao: dest, phase: .arrival, flight: s)
            if let h = FlightHelpers.mostCommon(s.turn?.destRunwayHistory ?? []) {
                r.record.runway = h
                r.autoFields.insert("runway")
            }
            return r
        }
        var r = RecordRequest(icao: s.origin ?? "LTFM", phase: .departure, flight: s)
        if !s.runway.isEmpty { r.record.runway = s.runway; r.autoFields.insert("runway") }
        if let sid = s.sid, !sid.isEmpty { r.record.procedure = sid; r.autoFields.insert("procedure") }
        if !s.stand.isEmpty { r.record.stand = s.stand; r.autoFields.insert("stand") }
        return r
    }
}

/// 20 saniyelik uçuş sonrası kayıt.
struct RecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = AirportStore.shared
    @State private var r: FlightRecord
    let auto: Set<String>
    let finish: Bool
    @EnvironmentObject var model: AppModel
    @State private var noteKind: AirportNote.Kind = .hotspot
    @State private var noteText = ""
    private let approaches = ["ILS", "RNP", "Visual", "VOR", L("Diğer", "Other")]

    init(request: RecordRequest) {
        _r = State(initialValue: request.record)
        auto = request.autoFields
        finish = request.finish
    }

    private var isArrival: Bool { r.phase == .arrival }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $r.phase) {
                        Text(L("Varış", "Arrival")).tag(FlightRecord.Phase.arrival)
                        Text(L("Kalkış", "Departure")).tag(FlightRecord.Phase.departure)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(L("Meydan", "Airport")).foregroundStyle(Palette.secondary)
                        Spacer()
                        Text("\(r.icao)" + (r.flight.isEmpty ? "" : " · \(r.flight)") + (r.aircraftType.isEmpty ? "" : " · \(r.aircraftType)"))
                            .font(.body.monospaced())
                    }
                    if let d = r.windDir, let sp = r.windSpeed {
                        HStack {
                            Text(L("Rüzgâr (METAR)", "Wind (METAR)")).foregroundStyle(Palette.secondary)
                            Spacer()
                            Text(String(format: "%03d° %d kt", d, sp))
                            AutoBadge()
                        }
                    }
                }

                Section(isArrival ? L("Pist ve yaklaşma", "Runway and approach") : L("Pist ve SID", "Runway and SID")) {
                    field(L("Pist", "Runway"), text: $r.runway, key: "runway", hint: "27R")
                    chips(recent(\.runway), selection: $r.runway)
                    field(isArrival ? "STAR" : "SID", text: $r.procedure, key: "procedure", hint: isArrival ? "BNN1X" : "ABC2D")
                    chips(recent(\.procedure), selection: $r.procedure)
                    if isArrival {
                        chips(approaches, selection: $r.approach, title: L("Yaklaşma", "Approach"))
                    }
                }

                Section(L("Yer", "Ground")) {
                    field(L("Taksi rotası", "Taxi route"), text: $r.taxi, key: "taxi", hint: "A, B, L33")
                    chips(recent(\.taxi), selection: $r.taxi)
                    field("Stand", text: $r.stand, key: "stand", hint: "C214")
                    field("APU", text: $r.apu, key: "apu", hint: isArrival ? L("gate'ten sonra 5 dk", "5 min after on-block") : L("off-block'tan 10 dk önce", "10 min before off-block"))
                }

                Section {
                    Picker(L("Tür", "Type"), selection: $noteKind) {
                        ForEach(AirportNote.Kind.ops) { Text($0.title).tag($0) }
                    }
                    TextField(L("Örn. B ve K kesişimi karışıyor", "e.g. the B/K intersection is confusing"), text: $noteText, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text(L("Meydan notu (isteğe bağlı)", "Airport note (optional)"))
                }

                Section {
                    Text(L("Kayıtlar meydan istatistiklerini oluşturur (\"%64 27R\" gibi). Kişisel bilgi içermez.", "Logs build the airport statistics (like \"64% 27R\"). No personal data is included."))
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle(finish ? L("Uçuşu bitir", "Finish flight") : L("Uçuş kaydı", "Flight log"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finish ? L("Atla, bitir", "Skip, finish") : L("Sonra", "Later")) {
                        if finish { Task { await model.finishFlight() } }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(finish ? L("Kaydet, bitir", "Save, finish") : L("Kaydet", "Save")) {
                        if hasRecord {
                            r.date = Date()
                            store.add(clean(r))
                        }
                        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !note.isEmpty { store.add(AirportNote(icao: r.icao, kind: noteKind, text: note)) }
                        if finish { Task { await model.finishFlight() } }
                        dismiss()
                    }
                    .bold()
                    .disabled(!hasRecord && noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                if r.windDir == nil, let m = await WeatherService.fetch([r.icao]).first?.metar, let w = Wind.parse(m) {
                    r.windDir = w.direction
                    r.windSpeed = w.speed
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hasRecord: Bool {
        !(r.runway.trimmingCharacters(in: .whitespaces).isEmpty && r.stand.isEmpty && r.taxi.isEmpty)
    }

    private func clean(_ x: FlightRecord) -> FlightRecord {
        var y = x
        y.runway = y.runway.trimmingCharacters(in: .whitespaces).uppercased()
        y.procedure = y.procedure.trimmingCharacters(in: .whitespaces).uppercased()
        y.taxi = y.taxi.trimmingCharacters(in: .whitespaces).uppercased()
        y.stand = y.stand.trimmingCharacters(in: .whitespaces).uppercased()
        y.apu = y.apu.trimmingCharacters(in: .whitespaces)
        return y
    }

    /// Bu meydanda bu aşamada en sık girilenler (hızlı seçim).
    private func recent(_ kp: KeyPath<FlightRecord, String>) -> [String] {
        AirportStats.distribution(store.records(r.icao).filter { $0.phase == r.phase }.map { $0[keyPath: kp] }, limit: 3).map(\.value)
    }

    private func field(_ title: String, text: Binding<String>, key: String, hint: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.secondary)
            TextField(hint, text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(key == "apu" ? .sentences : .characters)
                .autocorrectionDisabled()
            if auto.contains(key) { AutoBadge() }
        }
    }

    @ViewBuilder
    private func chips(_ values: [String], selection: Binding<String>, title: String? = nil) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let title { Text(title).font(.caption).foregroundStyle(Palette.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(values, id: \.self) { v in
                            let on = selection.wrappedValue.uppercased() == v.uppercased()
                            Button { selection.wrappedValue = v } label: {
                                Text(v).font(.subheadline.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(on ? Palette.stand.opacity(0.25) : Palette.card2, in: Capsule())
                                    .overlay(Capsule().stroke(on ? Palette.stand : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}

struct AutoBadge: View {
    var body: some View {
        Text(L("OTOMATİK", "AUTO")).font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .foregroundStyle(Palette.outbound)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.outbound.opacity(0.6)))
    }
}
