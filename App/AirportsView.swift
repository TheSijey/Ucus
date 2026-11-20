import SwiftUI

/// Meydanlar sekmesi: bu turun meydanları, kayıtlı meydanlar ve ICAO ile arama.
struct AirportsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session = FlightSession.shared
    @ObservedObject var store = AirportStore.shared
    @State private var search = ""
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let hits = AirportDB.search(search)
                if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section(L("Arama", "Search")) {
                        if hits.isEmpty {
                            Text(L("Bulunamadı. ICAO (EGLL), IATA (LHR) ya da şehrin İngilizce adını (London) dene.", "Not found. Try ICAO (EGLL), IATA (LHR) or the city name (London)."))
                                .font(.footnote).foregroundStyle(Palette.secondary)
                        }
                        ForEach(hits, id: \.self) { h in
                            NavigationLink(value: h.icao) {
                                AirportRow(icao: h.icao, subtitle: h.iata.isEmpty ? nil : h.iata)
                            }
                        }
                    }
                }
                if let s = session.state {
                    Section(s.isPreview == true ? L("Bu tur · ön izleme", "This trip · preview") : L("Bu tur", "This trip")) {
                        ForEach(FlightHelpers.allAirports(s), id: \.self) { icao in
                            NavigationLink(value: icao) {
                                AirportRow(icao: icao, subtitle: icao == FlightHelpers.destICAO(s) ? L("Varış", "Arrival") : (icao == FlightHelpers.airports(s).first ? L("Kalkış", "Departure") : L("Ara bacak", "Leg")))
                            }
                        }
                        Button { model.recordRequest = RecordRequest.forCurrent(s) } label: {
                            Label(L("Bu uçuşu kaydet (20 sn)", "Log this flight (20 s)"), systemImage: "square.and.pencil")
                        }
                    }
                }
                if session.state == nil, let s = session.last {
                    Section(L("Son uçuşun · \(s.flight)", "Your last flight · \(s.flight)")) {
                        ForEach(FlightHelpers.allAirports(s), id: \.self) { icao in
                            HStack {
                                NavigationLink(value: icao) { AirportRow(icao: icao, subtitle: nil) }
                                Menu {
                                    Button { model.recordRequest = RecordRequest(icao: icao, phase: .arrival, flight: s) } label: {
                                        Label(L("Varış kaydı", "Arrival log"), systemImage: "airplane.arrival")
                                    }
                                    Button { model.recordRequest = RecordRequest(icao: icao, phase: .departure, flight: s) } label: {
                                        Label(L("Kalkış kaydı", "Departure log"), systemImage: "airplane.departure")
                                    }
                                } label: {
                                    Image(systemName: "square.and.pencil").font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(L("\(icao) için kayıt ekle", "Add a log for \(icao)"))
                            }
                        }
                        Text(L("Uçuş bittikten sonra 24 saat burada durur; kayıt ve not ekleyebilirsin.", "Stays here for 24 hours after the flight so you can add logs and notes."))
                            .font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
                let tracked = session.state.map { FlightStore.normalizeFlight($0.flight) }
                if let next = model.store.upcoming.first(where: { FlightStore.normalizeFlight($0.flight) != tracked }),
                   let aps = next.airports, !aps.isEmpty {
                    Section(L("Sıradaki uçuşun · \(next.flight) · \(UTCFormat.shortDay(next.date))", "Your next flight · \(next.flight) · \(UTCFormat.shortDay(next.date))")) {
                        ForEach(aps, id: \.self) { icao in
                            NavigationLink(value: icao) { AirportRow(icao: icao, subtitle: nil) }
                        }
                    }
                }
                let recent = RecentAirports.list.filter { icao in
                    !(session.state.map { FlightHelpers.allAirports($0).contains(icao) } ?? false)
                }
                if !recent.isEmpty {
                    Section(L("Son baktıkların", "Recently viewed")) {
                        ForEach(recent, id: \.self) { icao in
                            NavigationLink(value: icao) { AirportRow(icao: icao, subtitle: nil) }
                        }
                    }
                }
                Section {
                    Text(CloudSync.enabled
                         ? L("Kayıtlar ve notlar diğer Uçuş kullanıcılarıyla paylaşılır. Ekip notudur; AIP, Jeppesen ve şirket prosedürlerinin yerine geçmez.",
                             "Logs and notes are shared with other Uçuş users. These are crew notes; they don't replace the AIP, Jeppesen or company procedures.")
                         : L("Şimdilik kayıtlar ve notlar sadece bu telefonda. Paylaşım açılınca diğer pilotların kayıtları da burada görünecek. Ekip notudur; AIP, Jeppesen ve şirket prosedürlerinin yerine geçmez.",
                             "For now logs and notes stay on this phone. Once sharing is on, other pilots' logs will show here too. These are crew notes; they don't replace the AIP, Jeppesen or company procedures."))
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .searchable(text: $search, prompt: L("Kod ya da şehir (LHR, London)", "Code or city (LHR, London)"))
            .autocorrectionDisabled()
            .navigationTitle(L("Meydanlar", "Airports"))
            .navigationDestination(for: String.self) { AirportDetailView(icao: $0) }
            .toolbar { CommonToolbar() }
            .onChange(of: model.openAirport) { _, icao in
                if let icao { path = [icao]; model.openAirport = nil }
            }
            .onAppear {
                if let icao = model.openAirport { path = [icao]; model.openAirport = nil }
            }
        }
    }
}

struct AirportRow: View {
    let icao: String
    let subtitle: String?
    @ObservedObject var store = AirportStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Text(icao).font(.headline.monospaced()).frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(AirportDB.city(icao: icao) ?? icao).font(.subheadline.bold())
                let n = store.records(icao).count, c = store.notes(icao).count
                Text([subtitle, L("\(n) kayıt · \(c) not", "\(n) logs · \(c) notes")].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
        }
    }
}

// MARK: - Meydan sayfası

struct AirportDetailView: View {
    enum Part: Hashable { case ops, weather, layover, comments }

    let icao: String
    @EnvironmentObject var model: AppModel
    @ObservedObject var store = AirportStore.shared
    @ObservedObject var session = FlightSession.shared
    @State private var part: Part = .ops
    @State private var onlyType = false
    @State private var similarWind = false
    @State private var currentWind: Int?
    @State private var metar: AirportWeather?
    @State private var composing: [AirportNote.Kind]?
    @State private var rating = false

    private var myType: String? {
        guard let t = session.state?.aircraftType, !t.isEmpty else { return nil }
        return t
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let w = metar {
                    let st = WeatherStatus(w)
                    Button { part = .weather } label: {
                        HStack(spacing: 8) {
                            Image(systemName: st.icon).foregroundStyle(st.color)
                            Text(st.isWarning ? st.short : (st.detail.isEmpty ? L("Sorun yok", "Fine") : st.detail))
                                .font(.subheadline.weight(st.isWarning ? .bold : .regular)).lineLimit(1)
                            Spacer()
                            Text(L("Hava", "Weather")).font(.caption.bold()).foregroundStyle(Palette.stand)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
                        }
                        .padding(12)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Picker("", selection: $part) {
                    Text(L("Operasyon", "Ops")).tag(Part.ops)
                    Text(L("Hava", "Weather")).tag(Part.weather)
                    Text(L("Layover", "Layover")).tag(Part.layover)
                    Text(L("Notlar", "Notes") + " \(store.notes(icao).filter { !$0.kind.isLayover }.count)").tag(Part.comments)
                }
                .pickerStyle(.segmented)
                if let st = store.cloudStatus {
                    Text(st).font(.caption).foregroundStyle(Palette.warn)
                }
                switch part {
                case .ops: ops
                case .weather: WeatherSection(fixed: icao)
                case .layover: layover
                case .comments: comments
                }
                Text(L("Ekip notudur. AIP, Jeppesen ve şirket prosedürlerinin yerine geçmez.", "Crew notes only. They don't replace the AIP, Jeppesen or company procedures."))
                    .font(.caption2).foregroundStyle(Palette.secondary)
            }
            .padding(16)
        }
        .background(Palette.bg)
        .navigationTitle(AirportDB.city(icao: icao).map { "\(icao) · \($0)" } ?? icao)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { model.recordRequest = RecordRequest(icao: icao, phase: .arrival) } label: { Label(L("Varış kaydı", "Arrival log"), systemImage: "airplane.arrival") }
                    Button { model.recordRequest = RecordRequest(icao: icao, phase: .departure) } label: { Label(L("Kalkış kaydı", "Departure log"), systemImage: "airplane.departure") }
                    Button { composing = AirportNote.Kind.ops } label: { Label(L("Operasyon notu", "Ops note"), systemImage: "text.bubble") }
                    Button { composing = AirportNote.Kind.layover } label: { Label(L("Layover bilgisi", "Layover info"), systemImage: "bed.double") }
                    Button { rating = true } label: { Label(L("Oteli puanla", "Rate the hotel"), systemImage: "star") }
                } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel(L("Ekle", "Add"))
            }
        }
        .refreshable { await store.load(icao) }
        .task {
            RecentAirports.add(icao)
            await store.load(icao)
            metar = await WeatherService.fetch([icao]).first
            if let m = metar?.metar, let wind = Wind.parse(m) { currentWind = wind.direction }
        }
        .sheet(item: Binding(get: { composing.map { KindList(kinds: $0) } }, set: { composing = $0?.kinds })) { list in
            NoteComposer(icao: icao, kinds: list.kinds)
        }
        .sheet(isPresented: $rating) { RatingSheet(icao: icao) }
    }

    // MARK: Operasyon

    private var filtered: [FlightRecord] {
        store.records(icao).filter { r in
            (!onlyType || myType == nil || r.aircraftType == myType) &&
            (!similarWind || AirportStats.similarWind(r.windDir, currentWind))
        }
    }

    @ViewBuilder
    private var ops: some View {
        let recs = filtered
        let arr = recs.filter { $0.phase == .arrival }
        let dep = recs.filter { $0.phase == .departure }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let w = currentWind {
                    FilterChip(title: L("Şu anki rüzgâr \(String(format: "%03d°", w))", "Current wind \(String(format: "%03d°", w))"), on: $similarWind)
                }
                if let t = myType { FilterChip(title: t, on: $onlyType) }
            }
        }
        if recs.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Henüz kayıt yok", "No logs yet")).font(.headline)
                    Text(L("İnişten sonra gelen bildirimle ya da sağ üstteki + ile 20 saniyelik kayıt ekle. İstatistikler kayıtlardan oluşur.",
                           "Add a 20-second log from the post-landing notification or the + at the top right. Statistics are built from logs."))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
            }
        }
        plainSummary(arr: arr)
        if !arr.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(L("Varış", "Arrival"), count: arr.count)
                    ShareLine(title: "STAR", shares: AirportStats.distribution(arr.map(\.procedure), limit: 2))
                    ShareBars(title: L("İniş pisti", "Landing runway"), shares: AirportStats.distribution(arr.map(\.runway)))
                    ShareLine(title: L("Yaklaşma", "Approach"), shares: AirportStats.distribution(arr.map(\.approach), limit: 2))
                    ShareLine(title: L("Taksi", "Taxi"), shares: AirportStats.distribution(arr.map(\.taxi), limit: 1))
                    ShareLine(title: L("Stand bölgesi", "Stand area"), shares: AirportStats.distribution(arr.map { AirportStats.standArea($0.stand) }, limit: 2))
                    LatestLine(title: "APU", value: arr.sorted { $0.date > $1.date }.first { !$0.apu.isEmpty }?.apu)
                }
            }
        }
        if !dep.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(L("Kalkış", "Departure"), count: dep.count)
                    ShareBars(title: L("Kalkış pisti", "Departure runway"), shares: AirportStats.distribution(dep.map(\.runway)))
                    ShareLine(title: "SID", shares: AirportStats.distribution(dep.map(\.procedure), limit: 2))
                    ShareLine(title: L("Taksi", "Taxi"), shares: AirportStats.distribution(dep.map(\.taxi), limit: 1))
                    LatestLine(title: "APU", value: dep.sorted { $0.date > $1.date }.first { !$0.apu.isEmpty }?.apu)
                }
            }
        }
        let rules = store.notes(icao).filter { $0.kind == .apu || $0.kind == .noise }
        if !rules.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("APU ve gürültü", "APU and noise")).font(.headline)
                    ForEach(rules.sorted { $0.createdAt > $1.createdAt }) { NoteRow(note: $0) }
                }
            }
        }
    }

    /// "27R'ye ineceksin · 10 inişin 7'si" gibi düz cümleler.
    @ViewBuilder
    private func plainSummary(arr: [FlightRecord]) -> some View {
        let windArr = currentWind.map { w in arr.filter { AirportStats.similarWind($0.windDir, w) } } ?? []
        let base = windArr.count >= 3 ? windArr : arr
        let rwy = AirportStats.distribution(base.map(\.runway), limit: 1).first
        let appr = AirportStats.distribution(base.map(\.approach), limit: 1).first
        let area = AirportStats.distribution(arr.map { AirportStats.standArea($0.stand) }, limit: 1).first
        let apu = arr.sorted { $0.date > $1.date }.first { !$0.apu.isEmpty }?.apu
            ?? store.notes(icao).filter { $0.kind == .apu }.max { $0.createdAt < $1.createdAt }?.text
        let hot = store.notes(icao).filter { $0.kind == .hotspot }.max { $0.createdAt < $1.createdAt }
        if rwy != nil || area != nil || apu != nil || hot != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(windArr.count >= 3 ? L("Bugünkü rüzgârla büyük ihtimalle:", "With today's wind, most likely:") : L("Genelde:", "Usually:"))
                    .font(.headline)
                if let rwy {
                    let n = base.filter { !$0.runway.isEmpty }.count
                    sentence("airplane.arrival", Palette.signOn, L("\(rwy.value)'ye ineceksin", "You'll land on \(rwy.value)"),
                             L("\(n) inişin \(rwy.count)'i", "\(rwy.count) of \(n) landings") + (appr.map { " · " + L("çoğu \($0.value)", "mostly \($0.value)") } ?? ""))
                }
                if let area {
                    sentence("parkingsign", Palette.stand, L("\(area.value) bölgesinde park", "Parking in the \(area.value) area"),
                             L("kayıtların %\(area.percent)'i", "%\(area.percent) of logs"))
                }
                if let apu { sentence("bolt.fill", Palette.outbound, "APU: \(apu)", nil) }
                if let hot { sentence("exclamationmark.triangle.fill", Palette.warn, hot.text, L("Hotspot", "Hotspot")) }
            }
        }
    }

    private func sentence(_ icon: String, _ color: Color, _ title: String, _ sub: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
                .frame(width: 40, height: 40).background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let sub { Text(sub).font(.subheadline).foregroundStyle(Palette.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Layover

    @ViewBuilder
    private var layover: some View {
        let notes = store.notes(icao).filter { $0.kind.isLayover }
        let latest: (AirportNote.Kind) -> AirportNote? = { k in notes.filter { $0.kind == k }.max { $0.createdAt < $1.createdAt } }
        let ratings = store.ratings(icao)
        if let tz = AirportTime.zone(icao) {
            HStack(spacing: 8) {
                TimelineView(.everyMinute) { ctx in
                    Tile(title: L("Yerel saat", "Local time"), value: FlightHelpers.local(ctx.date, tz))
                }
                if let p = session.state?.pickupAt, session.state?.origin == icao {
                    Tile(title: L("Otel çıkışı", "Hotel pickup"), value: FlightHelpers.local(p, tz), color: Palette.signOn)
                }
            }
        }
        if notes.isEmpty && ratings.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Layover bilgisi yok", "No layover info")).font(.headline)
                    Text(L("Otel, servis yeri, laundry hakkı ya da mekân önerisi eklemek için sağ üstteki +'ya dokun.", "Tap + at the top right to add the hotel, pickup point, laundry allowance or a place tip."))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Otel", "Hotel")).font(.headline)
                    ForEach([AirportNote.Kind.hotel, .pickup, .laundry, .breakfast], id: \.self) { k in
                        if let n = latest(k) { LatestLine(title: k.title, value: n.text) }
                    }
                    if !ratings.isEmpty {
                        let avg: (KeyPath<HotelRating, Int>) -> String = { kp in
                            let v = ratings.map { $0[keyPath: kp] }.filter { $0 > 0 }
                            return v.isEmpty ? "—" : String(format: "%.1f/5", Double(v.reduce(0, +)) / Double(v.count))
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            Tile(title: L("Spor salonu", "Gym"), value: avg(\.gym))
                            Tile(title: "Wi-Fi", value: avg(\.wifi))
                            Tile(title: L("Karanlık oda", "Dark room"), value: avg(\.dark))
                            Tile(title: L("Sessizlik", "Quiet"), value: avg(\.quiet))
                        }
                        Text(L("\(ratings.count) puanlama", "\(ratings.count) ratings")).font(.caption2).foregroundStyle(Palette.secondary)
                    }
                }
            }
            let places = notes.filter { $0.kind == .place }.sorted { $0.createdAt > $1.createdAt }
            if !places.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Çevre · ekip önerileri", "Nearby · crew tips")).font(.headline)
                        ForEach(places) { NoteRow(note: $0) }
                    }
                }
            }
            let other = notes.filter { $0.kind == .safety || $0.kind == .practical }
            if !other.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Bilmekte fayda var", "Good to know")).font(.headline)
                        ForEach(other) { NoteRow(note: $0) }
                    }
                }
            }
        }
        Text(L("Oda numarası gibi kişisel bilgiler paylaşma.", "Don't share personal details such as room numbers."))
            .font(.caption2).foregroundStyle(Palette.secondary)
    }

    // MARK: Yorumlar

    @ViewBuilder
    private var comments: some View {
        let notes = store.notes(icao).filter { !$0.kind.isLayover && $0.kind != .apu && $0.kind != .noise }
        let votes = store.votes(icao)
        if notes.isEmpty {
            Card {
                Text(L("Henüz yorum yok. Hotspot, ATC, crew bus ya da handling notu eklemek için +'ya dokun.", "No comments yet. Tap + to add a hotspot, ATC, crew bus or handling note."))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
            }
        }
        ForEach(notes.sorted { score($0, votes) > score($1, votes) }) { n in
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    NoteRow(note: n)
                    let mine = votes.first { $0.noteID == n.id && $0.author == Identity.id }
                    let valid = votes.filter { $0.noteID == n.id && $0.valid }
                    let changedCount = votes.filter { $0.noteID == n.id && !$0.valid }.count
                    let lastDate = (valid.map(\.date) + [n.createdAt]).max() ?? n.createdAt
                    HStack(spacing: 8) {
                        Button { store.vote(n, valid: true) } label: {
                            Label(L("Geçerli · \(valid.count)", "Still valid · \(valid.count)"), systemImage: mine?.valid == true ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .buttonStyle(.bordered).tint(Palette.outbound)
                        Button { store.vote(n, valid: false) } label: {
                            Label(L("Değişti · \(changedCount)", "Changed · \(changedCount)"), systemImage: mine?.valid == false ? "xmark.circle.fill" : "xmark.circle")
                        }
                        .buttonStyle(.bordered).tint(Palette.warn)
                        Spacer()
                        if n.author == Identity.id {
                            Button(role: .destructive) { store.delete(n) } label: { Image(systemName: "trash") }
                                .accessibilityLabel(L("Notu sil", "Delete note"))
                        }
                    }
                    .font(.caption)
                    Text(L("Son onay: ", "Last confirmed: ") + lastDate.formatted(.dateTime.day().month(.abbreviated).year().locale(Lang.locale)))
                        .font(.caption2).foregroundStyle(Palette.secondary)
                }
            }
            .opacity(Date().timeIntervalSince(last(n, votes)) > 90 * 86_400 || changed(n, votes) > validCount(n, votes) ? 0.55 : 1)
        }
    }

    private func validCount(_ n: AirportNote, _ v: [NoteVote]) -> Int { v.filter { $0.noteID == n.id && $0.valid }.count }
    private func changed(_ n: AirportNote, _ v: [NoteVote]) -> Int { v.filter { $0.noteID == n.id && !$0.valid }.count }
    private func last(_ n: AirportNote, _ v: [NoteVote]) -> Date {
        (v.filter { $0.noteID == n.id && $0.valid }.map(\.date) + [n.createdAt]).max() ?? n.createdAt
    }
    private func score(_ n: AirportNote, _ v: [NoteVote]) -> Double {
        Double(validCount(n, v) - 2 * changed(n, v)) - Date().timeIntervalSince(last(n, v)) / (30 * 86_400)
    }
}

private struct KindList: Identifiable {
    let kinds: [AirportNote.Kind]
    var id: String { kinds.map(\.rawValue).joined() }
}

/// Meydanın saat dilimi (AirportDB'de yoksa kalkış meydanınınki).
enum AirportTime {
    @MainActor static func zone(_ icao: String) -> TimeZone? {
        if icao.hasPrefix("LT") { return TimeZone(identifier: "Europe/Istanbul") }
        if let s = FlightSession.shared.state, s.origin == icao { return s.originTimeZone }
        return nil
    }
}

// MARK: - Küçük parçalar

struct FilterChip: View {
    let title: String
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            Text(title).font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(on ? Palette.stand.opacity(0.22) : Palette.card, in: Capsule())
                .overlay(Capsule().stroke(on ? Palette.stand : Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct SectionTitle: View {
    let title: String
    let count: Int
    init(_ title: String, count: Int) { self.title = title; self.count = count }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(Palette.stand)
            Spacer()
            Text(L("\(count) kayıttan", "from \(count) logs")).font(.caption2).foregroundStyle(Palette.secondary)
        }
    }
}

struct ShareLine: View {
    let title: String
    let shares: [Share]
    var body: some View {
        if !shares.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).foregroundStyle(Palette.secondary)
                Spacer()
                Text(shares.map { "\($0.value) %\($0.percent)" }.joined(separator: " · "))
                    .font(.subheadline.bold()).multilineTextAlignment(.trailing)
            }
        }
    }
}

struct LatestLine: View {
    let title: String
    let value: String?
    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).foregroundStyle(Palette.secondary)
                Spacer()
                Text(value).font(.subheadline.bold()).multilineTextAlignment(.trailing)
            }
        }
    }
}

struct ShareBars: View {
    let title: String
    let shares: [Share]
    var body: some View {
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline).foregroundStyle(Palette.secondary)
                ForEach(Array(shares.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        Text(s.value).font(.subheadline.bold().monospaced()).frame(width: 44, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.card2)
                                Capsule().fill(i == 0 ? Palette.signOn : Palette.signOn.opacity(0.45))
                                    .frame(width: max(6, g.size.width * CGFloat(s.percent) / 100))
                            }
                        }
                        .frame(height: 10)
                        Text("%\(s.percent)").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(s.value) %\(s.percent)")
                }
            }
        }
    }
}

struct NoteRow: View {
    let note: AirportNote
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(note.kind == .place && !note.placeCategory.isEmpty ? note.placeCategory : note.kind.title)
                .font(.caption2.bold())
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(note.kind.color, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.black)
                .fixedSize()
            Text(note.text).font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Not ekleme

struct NoteComposer: View {
    let icao: String
    let kinds: [AirportNote.Kind]
    @Environment(\.dismiss) private var dismiss
    @State private var kind: AirportNote.Kind
    @State private var text = ""
    @State private var placeCategory = "Kahve"
    private let placeCategories = ["Kahve", "Yemek", "Market", "Koşu", "Eczane", "Diğer"]

    init(icao: String, kinds: [AirportNote.Kind]) {
        self.icao = icao
        self.kinds = kinds
        _kind = State(initialValue: kinds.first ?? .other)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Tür", "Type")) {
                    Picker(L("Tür", "Type"), selection: $kind) {
                        ForEach(kinds) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if kind == .place {
                        Picker(L("Mekân türü", "Place type"), selection: $placeCategory) {
                            ForEach(placeCategories, id: \.self) { Text(L($0, english($0))).tag($0) }
                        }
                    }
                }
                Section {
                    TextField(placeholder, text: $text, axis: .vertical).lineLimit(2...6)
                } footer: {
                    Text(L("Kısa ve net yaz. Oda numarası gibi kişisel bilgi paylaşma.", "Keep it short. Don't share personal details such as room numbers."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle("\(icao) · " + L("Not ekle", "Add note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Vazgeç", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Kaydet", "Save")) {
                        AirportStore.shared.add(AirportNote(icao: icao, kind: kind, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                                            placeCategory: kind == .place ? L(placeCategory, english(placeCategory)) : ""))
                        dismiss()
                    }
                    .bold()
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func english(_ tr: String) -> String {
        ["Kahve": "Coffee", "Yemek": "Food", "Market": "Grocery", "Koşu": "Running", "Eczane": "Pharmacy", "Diğer": "Other"][tr] ?? tr
    }

    private var placeholder: String {
        switch kind {
        case .hotspot: L("Örn. B ve K kesişimi karışıyor", "e.g. the B/K intersection is confusing")
        case .atc: L("Örn. inişten sonra hızlı çıkış istiyorlar", "e.g. they ask for a quick runway exit")
        case .crewBus: L("Örn. remote standda bekleme uzun", "e.g. long wait at remote stands")
        case .apu: L("Örn. gate'e girdikten sonra 5 dk içinde kapat", "e.g. shut down within 5 min after on-block")
        case .noise: L("Örn. 23:30–06:00 kısıtlı", "e.g. restricted 23:30–06:00")
        case .hotel: L("Otelin adı ve havalimanına uzaklığı", "Hotel name and distance to the airport")
        case .pickup: L("Örn. ana girişin sol tarafı", "e.g. left side of the main entrance")
        case .laundry: L("Örn. günlük 2 parça", "e.g. 2 items per day")
        case .breakfast: L("Örn. 06:30–10:30", "e.g. 06:30–10:30")
        case .place: L("Mekânın adı ve neden iyi olduğu", "Place name and why it's good")
        case .safety: L("Örn. geceleri metroya yalnız yürüme", "e.g. don't walk to the metro alone at night")
        case .practical: L("Örn. lobide ATM var", "e.g. ATM in the lobby")
        default: L("Notun", "Your note")
        }
    }
}

struct RatingSheet: View {
    let icao: String
    @Environment(\.dismiss) private var dismiss
    @State private var r: HotelRating

    init(icao: String) {
        self.icao = icao
        _r = State(initialValue: AirportStore.shared.local.ratings.first { $0.icao == icao && $0.author == Identity.id } ?? HotelRating(icao: icao))
    }

    var body: some View {
        NavigationStack {
            Form {
                stars(L("Spor salonu", "Gym"), \.gym)
                stars("Wi-Fi", \.wifi)
                stars(L("Karanlık oda", "Dark room"), \.dark)
                stars(L("Sessizlik", "Quiet"), \.quiet)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle(L("Oteli puanla", "Rate the hotel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Vazgeç", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Kaydet", "Save")) {
                        r.date = Date()
                        AirportStore.shared.add(r)
                        dismiss()
                    }.bold()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func stars(_ title: String, _ kp: WritableKeyPath<HotelRating, Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ForEach(1...5, id: \.self) { i in
                Button { r[keyPath: kp] = i } label: {
                    Image(systemName: i <= r[keyPath: kp] ? "star.fill" : "star")
                        .foregroundStyle(Palette.signOn)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(i)/5")
            }
        }
    }
}

/// Son bakılan meydanlar (en fazla 5).
enum RecentAirports {
    private static let key = "recentAirports"
    static var list: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func add(_ icao: String) {
        var l = list.filter { $0 != icao }
        l.insert(icao, at: 0)
        UserDefaults.standard.set(Array(l.prefix(5)), forKey: key)
    }
}
