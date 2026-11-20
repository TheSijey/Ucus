import SwiftUI

/// Brifing: uçuş özeti, kabin arızaları, el yazısı not, ekip notu ve hava (METAR, TAF, pist rüzgârı).
struct BriefingView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared
    @ObservedObject var store = BriefingStore.shared
    @State private var editing: CabinDefect?
    @State private var showHandwriting = false
    @State private var presenting = false
    @FocusState private var noteFocused: Bool
    @State private var weather: [AirportWeather] = []
    @ObservedObject var notams = NotamStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = session.state {
                    let k = BriefingStore.key(for: s)
                    let notes = store.notes(k)
                    ScrollViewReader { proxy in
                        VStack(spacing: 12) {
                            checklist(s, k, notes, proxy)
                            flightCard(s).id("flight")
                            if let dest = FlightHelpers.destICAO(s), !s.isOutstation || dest != "LTFM" {
                                AirportDigest(icao: dest)
                            }
                            NotamCard(state: s).id("notam")
                            defectsCard(k, notes).id("defects")
                            DGCard(key: k).id("dg")
                            handwritingCard(k, notes).id("note")
                            crewNoteCard(k, notes)
                        }
                        .padding(16)
                    }
                    .task(id: s.updatedAt) { weather = await WeatherService.fetch(FlightHelpers.airports(s)) }
                    .sheet(item: $editing) { d in
                        DefectEditor(defect: d, isNew: !notes.defects.contains { $0.id == d.id }) { result in
                            store.update(k) { n in
                                if let result {
                                    if let i = n.defects.firstIndex(where: { $0.id == result.id }) { n.defects[i] = result }
                                    else { n.defects.append(result) }
                                } else {
                                    n.defects.removeAll { $0.id == d.id }
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showHandwriting) {
                        HandwritingSheet(data: notes.drawing) { data in
                            store.update(k) { $0.drawing = data }
                        }
                    }
                    .fullScreenCover(isPresented: $presenting) {
                        PresentationView(state: s, notes: notes)
                    }
                } else {
                    EmptyFlightView().padding(.top, 60).frame(maxWidth: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg)
            .navigationDestination(for: String.self) { AirportDetailView(icao: $0) }
            .navigationTitle(L("Brifing", "Briefing"))
            .toolbar {
                CommonToolbar()
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button(L("Bitti", "Done")) { noteFocused = false } }
                }
            }
            .refreshable { await model.refresh() }
        }
    }

    // MARK: Kontrol listesi

    private enum Mark { case ok, warn, alert(Int), todo, info }

    private func checklist(_ s: FlightAttributes.ContentState, _ k: String, _ notes: BriefingNotes, _ proxy: ScrollViewProxy) -> some View {
        let statuses = weather.map(WeatherStatus.init)
        let warnIndex = statuses.firstIndex { $0.isWarning }
        let pkg = notams.packages[k]
        let critical = (pkg.map { NotamFilter.relevant($0.notams, s) } ?? []).filter { $0.level == .critical }
        let dg = notes.dgItems ?? []
        let hasNote = !notes.crewNote.isEmpty || notes.drawing != nil
        return Card(padding: 0) {
            VStack(spacing: 0) {
                row(.ok, L("Uçuş bilgisi", "Flight details"),
                    [FlightHelpers.duration(s.departureTime, s.turn?.outboundArrival).map { L("Blok", "Block") + " \($0)" }, s.registration, s.aircraftType]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")) { withAnimation { proxy.scrollTo("flight", anchor: .top) } }
                divider
                row(weather.isEmpty ? .todo : (warnIndex != nil ? .warn : .ok), L("Hava", "Weather"),
                    warnIndex.map { "\(WeatherStatus.city(weather[$0].icao, s)): \(statuses[$0].short)" }
                        ?? (weather.isEmpty ? L("Yükleniyor…", "Loading…") : L("Meydanlarda sorun yok", "No issues at the airports")),
                    action: L("Hava sekmesinde aç", "Open in Weather")) { model.tab = .weather }
                divider
                row(pkg == nil ? .todo : (critical.isEmpty ? .ok : .alert(critical.count)), "NOTAM",
                    pkg == nil ? L("Briefing PDF'ini ekle", "Add the briefing PDF")
                        : (critical.isEmpty ? L("Kritik NOTAM yok", "No critical NOTAMs")
                           : critical.prefix(2).map { $0.summary ?? NotamDecoder.decode($0.text) }.joined(separator: " · "))) {
                    withAnimation { proxy.scrollTo("notam", anchor: .top) }
                }
                divider
                row(notes.defects.isEmpty ? .ok : .info, L("Kabin arızaları", "Cabin defects"),
                    notes.defects.isEmpty ? L("Yok", "None") : notes.defects.map { "\($0.category.title) \($0.location)" }.joined(separator: " · ")) {
                    withAnimation { proxy.scrollTo("defects", anchor: .top) }
                }
                divider
                row(dg.isEmpty ? .ok : .info, L("Tehlikeli madde", "Dangerous goods"),
                    dg.isEmpty ? L("Uçakta DG yok", "No DG on board") : dg.map(\.drill).filter { !$0.isEmpty }.joined(separator: ", ")) {
                    withAnimation { proxy.scrollTo("dg", anchor: .top) }
                }
                divider
                row(hasNote ? .ok : .todo, L("Ekibe notun", "Your crew note"),
                    hasNote ? L("Var", "Added") : L("İstersen yaz ya da kalemle çiz", "Type or draw one if you like")) {
                    withAnimation { proxy.scrollTo("note", anchor: .top) }
                }
                Button { presenting = true } label: {
                    Label(L("Ekibe göster", "Show the crew"), systemImage: "rectangle.on.rectangle")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.stand)
                .foregroundStyle(.black)
                .padding(14)
            }
        }
    }

    private var divider: some View { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62) }

    private func row(_ mark: Mark, _ title: String, _ detail: String, action: String? = nil, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                markView(mark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold())
                    Text(detail).font(.footnote).foregroundStyle(detailColor(mark)).lineLimit(2)
                    if let action { Text(action).font(.caption.bold()).foregroundStyle(Palette.stand) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func markView(_ m: Mark) -> some View {
        switch m {
        case .ok:
            Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(Palette.outbound)
                .frame(width: 34, height: 34).background(Palette.outbound.opacity(0.15), in: Circle())
        case .warn:
            Text("!").font(.headline.weight(.black)).foregroundStyle(Palette.warn)
                .frame(width: 34, height: 34).background(Palette.warn.opacity(0.18), in: Circle())
        case .alert(let n):
            Text("\(n)").font(.subheadline.weight(.black)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
                .frame(width: 34, height: 34).background(Color.red.opacity(0.18), in: Circle())
        case .info:
            Image(systemName: "info").font(.subheadline.bold()).foregroundStyle(Palette.stand)
                .frame(width: 34, height: 34).background(Palette.stand.opacity(0.15), in: Circle())
        case .todo:
            Circle().strokeBorder(Palette.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 34, height: 34)
        }
    }

    private func detailColor(_ m: Mark) -> Color {
        switch m {
        case .warn: Color(red: 1, green: 0.76, blue: 0.4)
        case .alert: Color(red: 1, green: 0.6, blue: 0.6)
        default: Palette.secondary
        }
    }

    // MARK: Uçuş

    private func flightCard(_ s: FlightAttributes.ContentState) -> some View {
        let dep = s.departureTime
        let arr = s.turn?.outboundArrival
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.flight).font(.title2.bold())
                    Text("\(s.originCode) → \(Display.text(s.destCode))")
                        .font(.headline).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button { presenting = true } label: {
                        Label(L("Sunum", "Present"), systemImage: "rectangle.on.rectangle")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.stand)
                    .foregroundStyle(.black)
                    .accessibilityHint(L("Brifingi ekibe göstermek için tam ekran açar", "Opens the briefing full screen to show the crew"))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    Tile(title: L("Kalkış", "Departure"), value: FlightHelpers.hm(dep))
                    Tile(title: L("Varış", "Arrival"), value: FlightHelpers.hm(arr))
                    Tile(title: L("Blok", "Block"), value: FlightHelpers.duration(dep, arr) ?? "—")
                    Tile(title: L("Tescil", "Reg."), value: s.registration)
                    Tile(title: L("Tip", "Type"), value: s.aircraftType)
                    Tile(title: "Stand", value: s.stand, color: Palette.stand)
                }
                if let r = s.turn?.returnFlight {
                    Text(L("Dönüş", "Return") + ": \(r) · \(FlightHelpers.hm(s.turn?.returnDeparture)) → \(FlightHelpers.hm(s.turn?.returnArrival))")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    // MARK: Kabin arızaları

    private func defectsCard(_ k: String, _ notes: BriefingNotes) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("Kabin arızaları", "Cabin defects")).font(.headline)
                    Spacer()
                    Text(L("Sadece bu uçuş · sende kalır", "This flight only · stays on your phone"))
                        .font(.caption2).foregroundStyle(Palette.secondary)
                }
                if notes.defects.isEmpty {
                    Text(L("Tech log'daki kabin arızalarını ekle, brifingde ekibe aktar.", "Add cabin defects from the tech log and pass them on at the briefing."))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
                ForEach(notes.defects) { d in
                    Button { editing = d } label: { DefectRow(defect: d) }
                        .buttonStyle(.plain)
                    if d.id != notes.defects.last?.id { Divider() }
                }
                Button { editing = CabinDefect() } label: {
                    Label(L("Arıza ekle", "Add defect"), systemImage: "plus")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                Text(L("Resmî kayıt tech log ve MEL'dir.", "The tech log and MEL are the official record."))
                    .font(.caption2).foregroundStyle(Palette.secondary)
            }
        }
    }

    // MARK: El yazısı

    private func handwritingCard(_ k: String, _ notes: BriefingNotes) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("El yazısı not", "Handwritten note")).font(.headline)
                    Spacer()
                    if notes.drawing != nil {
                        Button(role: .destructive) { store.update(k) { $0.drawing = nil } } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(L("El yazısı notu sil", "Delete handwritten note"))
                    }
                }
                Button { showHandwriting = true } label: {
                    if let data = notes.drawing {
                        DrawingPreview(data: data)
                            .padding(8)
                            .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Label(L("Kalemle yaz", "Write by hand"), systemImage: "pencil.tip.crop.circle")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Ekip notu

    private func crewNoteCard(_ k: String, _ notes: BriefingNotes) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Ekibe ek notum", "My note to the crew")).font(.headline)
                TextField(L("Örn. dönüşte catering geç gelebilir", "e.g. catering may be late on the return"),
                          text: Binding(get: { store.notes(k).crewNote },
                                        set: { v in store.update(k) { $0.crewNote = v } }),
                          axis: .vertical)
                    .lineLimit(2...6)
                    .focused($noteFocused)
                    .padding(10)
                    .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct DefectRow: View {
    let defect: CabinDefect
    var big = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(defect.category.title, systemImage: defect.category.icon)
                .font((big ? Font.subheadline : .caption).bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(defect.category.color, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(.black)
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(defect.headline).font(big ? .title3.bold() : .subheadline.bold())
                if !defect.note.isEmpty {
                    Text(defect.note).font(big ? .body : .footnote).foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Arıza ekle / düzenle. Sonuç nil ise silindi.
struct DefectEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var defect: CabinDefect
    let isNew: Bool
    let onDone: (CabinDefect?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Kategori", "Category")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(DefectCategory.allCases) { c in
                            Button { defect.category = c } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: c.icon).font(.title3)
                                    Text(c.title).font(.caption2.bold()).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(defect.category == c ? Palette.stand.opacity(0.25) : Palette.card2,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(defect.category == c ? Palette.stand : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(defect.category == c ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(L("Konum", "Location")) {
                    TextField(L("Örn. L2, 23C, arka galley", "e.g. L2, 23C, aft galley"), text: $defect.location)
                        .textInputAutocapitalization(.characters)
                }
                Section(L("Kabine etkisi", "Effect on the cabin")) {
                    ForEach(DefectImpact.allCases) { i in
                        Toggle(i.title, isOn: Binding(
                            get: { defect.impacts.contains(i) },
                            set: { on in
                                if on { defect.impacts.append(i) } else { defect.impacts.removeAll { $0 == i } }
                            }))
                    }
                }
                Section(L("Kabine not", "Note for the cabin")) {
                    TextField(L("Örn. ön kabin yolcuları arka tuvalete", "e.g. forward passengers use the aft lavatory"),
                              text: $defect.note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if !isNew {
                    Section {
                        Button(L("Arızayı sil", "Delete defect"), role: .destructive) {
                            onDone(nil)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle(isNew ? L("Kabin arızası", "Cabin defect") : L("Arızayı düzenle", "Edit defect"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Vazgeç", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Kaydet", "Save")) { onDone(defect); dismiss() }.bold()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Sunum modu: brifingi ekibe göstermek için büyük yazıyla tam ekran; ekran kapanmaz.
struct PresentationView: View {
    @Environment(\.dismiss) private var dismiss
    let state: FlightAttributes.ContentState
    let notes: BriefingNotes

    var body: some View {
        let s = state
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 34)).foregroundStyle(Palette.secondary)
                    }
                    .accessibilityLabel(L("Kapat", "Close"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.flight).font(.system(size: 44, weight: .heavy))
                    Text("\(s.originCode) → \(Display.text(s.destCode))")
                        .font(.system(size: 30, weight: .bold)).foregroundStyle(Palette.stand)
                    Text([
                        L("Kalkış", "Departure") + " \(FlightHelpers.hm(s.departureTime))",
                        FlightHelpers.duration(s.departureTime, s.turn?.outboundArrival).map { L("Blok", "Block") + " \($0)" },
                        s.registration.isEmpty ? nil : s.registration,
                    ].compactMap { $0 }.joined(separator: " · "))
                    .font(.title2).foregroundStyle(.white.opacity(0.85))
                }
                if !notes.defects.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L("Kabin arızaları", "Cabin defects")).font(.title2.bold()).foregroundStyle(Palette.warn)
                        ForEach(notes.defects) { DefectRow(defect: $0, big: true) }
                    }
                }
                if let dg = notes.dgItems, !dg.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Uçakta DG", "Dangerous goods")).font(.title2.bold()).foregroundStyle(Palette.warn)
                        ForEach(dg) { item in
                            Text(([item.drill, item.un, item.position].filter { !$0.isEmpty }).joined(separator: " · "))
                                .font(.title2.bold())
                        }
                    }
                }
                if let data = notes.drawing {
                    DrawingPreview(data: data)
                        .frame(maxHeight: 360)
                }
                if !notes.crewNote.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Not", "Note")).font(.title2.bold()).foregroundStyle(Palette.warn)
                        Text(notes.crewNote).font(.title2)
                    }
                }
                if notes.isEmpty {
                    Text(L("Kabin arızası ya da not yok.", "No cabin defects or notes."))
                        .font(.title2).foregroundStyle(Palette.secondary)
                }
            }
            .padding(24)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension FlightAttributes.ContentState {
    /// Varış kodu: dönüş bilgisindeki IATA, yoksa CDM'deki varış.
    var destCode: String {
        if let d = turn?.destIATA, !d.isEmpty { return d }
        return destination
    }
}

/// Varış meydanının özeti (Meydanlar verisinden): beklenen pist, stand bölgesi, son notlar.
struct AirportDigest: View {
    let icao: String
    @ObservedObject var store = AirportStore.shared

    var body: some View {
        let arr = store.records(icao).filter { $0.phase == .arrival }
        let rwy = AirportStats.distribution(arr.map(\.runway), limit: 1).first
        let area = AirportStats.distribution(arr.map { AirportStats.standArea($0.stand) }, limit: 1).first
        let notes = store.notes(icao).filter { [.hotspot, .apu, .noise, .atc].contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }.prefix(3)
        NavigationLink(value: icao) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("\(icao) notlarından", "From \(icao) notes")).font(.headline).foregroundStyle(Palette.stand)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
                    }
                    if rwy == nil && notes.isEmpty {
                        Text(L("Henüz kayıt yok. Meydan sayfasını açmak için dokun.", "No logs yet. Tap to open the airport page."))
                            .font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                    if rwy != nil || area != nil {
                        HStack(spacing: 8) {
                            if let rwy { Tile(title: L("Beklenen pist", "Expected runway"), value: "\(rwy.value) %\(rwy.percent)") }
                            if let area { Tile(title: L("Stand bölgesi", "Stand area"), value: "\(area.value) %\(area.percent)") }
                        }
                    }
                    ForEach(Array(notes)) { NoteRow(note: $0) }
                }
            }
        }
        .buttonStyle(.plain)
        .task { await store.load(icao) }
    }
}
