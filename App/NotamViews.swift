import SwiftUI
import UniformTypeIdentifiers

/// Brifing'deki NOTAM kartı: içe aktarma ve kritik NOTAM'ların özeti.
struct NotamCard: View {
    let state: FlightAttributes.ContentState
    @ObservedObject var store = NotamStore.shared
    @State private var importing = false
    @State private var pasting = false
    @State private var message: String?

    private var key: String { BriefingStore.key(for: state) }

    var body: some View {
        let pkg = store.packages[key]
        let relevant = pkg.map { NotamFilter.relevant($0.notams, state, alternates: $0.alternates ?? []) } ?? []
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NOTAM").font(.headline)
                    Spacer()
                    if store.summarizing { ProgressView().controlSize(.small) }
                    Menu {
                        Button { importing = true } label: { Label(L("PDF / dosya içe aktar", "Import PDF / file"), systemImage: "doc") }
                        Button { pasting = true } label: { Label(L("Metni yapıştır", "Paste text"), systemImage: "doc.on.clipboard") }
                        if pkg != nil {
                            Button(role: .destructive) { store.remove(key) } label: { Label(L("NOTAM'ları kaldır", "Remove NOTAMs"), systemImage: "trash") }
                        }
                    } label: { Image(systemName: pkg == nil ? "plus.circle" : "ellipsis.circle").font(.title3) }
                    .accessibilityLabel(L("NOTAM seçenekleri", "NOTAM options"))
                }
                if let pkg {
                    HStack(spacing: 8) {
                        ForEach(Notam.Level.allCases, id: \.self) { lv in
                            let c = relevant.filter { $0.level == lv }.count
                            Tile(title: lv.title, value: "\(c)", color: c > 0 ? lv.color : .primary)
                        }
                    }
                    Text(groupCounts(pkg, relevant)).font(.caption).foregroundStyle(Palette.secondary)
                    if relevant.contains(where: { $0.level != .info }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Uçuşun için önemli", "Important for your flight")).font(.subheadline.bold())
                            NotamDigest(notams: relevant, state: state, alternates: pkg.alternates ?? [], perGroup: 4)
                        }
                        .padding(12)
                        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(L("Uçuş saatlerinde operasyonu etkileyen NOTAM bulunmadı.", "No NOTAMs affecting operations at your flight times."))
                            .font(.subheadline).foregroundStyle(Palette.outbound)
                    }
                    NavigationLink {
                        NotamListView(key: key, state: state)
                    } label: {
                        Text(L("Tümünü gör · \(pkg.notams.count) NOTAM", "See all · \(pkg.notams.count) NOTAMs"))
                            .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    Text(L("\(pkg.source) · \(pkg.importedAt.formatted(.dateTime.hour().minute()))", "\(pkg.source) · \(pkg.importedAt.formatted(.dateTime.hour().minute()))"))
                        .font(.caption2).foregroundStyle(Palette.secondary)
                } else {
                    Text(L("Briefing paketindeki NOTAM'ları içe aktar: uçuş saatinde geçerli olanlar süzülür, kritik olanlar öne çıkar. Briefing PDF'ini Dosyalar'dan ya da paylaş menüsünden \"Uçuş\" ile de açabilirsin.",
                           "Import the NOTAMs from your briefing pack: those valid at flight time are filtered and critical ones come first. You can also open the briefing PDF with \"Uçuş\" from Files or the share menu."))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                    Button { importing = true } label: {
                        Label(L("Briefing PDF'ini içe aktar", "Import briefing PDF"), systemImage: "doc.badge.plus")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                }
                if let message { Text(message).font(.caption).foregroundStyle(Palette.warn) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .plainText, .text]) { result in
            if case .success(let url) = result { load(url) }
        }
        .sheet(isPresented: $pasting) {
            PasteNotamSheet { text in
                let n = store.importText(text, source: L("Yapıştırılan metin", "Pasted text"), key: key, airports: FlightHelpers.airports(state))
                message = n == 0 ? L("Metinde NOTAM bulunamadı.", "No NOTAMs found in the text.") : nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importNotamFile)) { note in
            if let url = note.object as? URL { load(url) }
        }
    }

    private func groupCounts(_ pkg: NotamPackage, _ relevant: [Notam]) -> String {
        let alts = pkg.alternates ?? []
        let origin = FlightHelpers.airports(state).first ?? "LTFM"
        let dest = FlightHelpers.destICAO(state)
        return NotamGroup.allCases.compactMap { g -> String? in
            let c = relevant.filter { NotamGroup.of($0, origin: origin, dest: dest, alternates: alts) == g }.count
            return c == 0 ? nil : "\(g.title) \(c)"
        }.joined(separator: " · ")
    }

    private func load(_ url: URL) {
        guard let text = NotamParser.pdfText(url), !text.isEmpty else {
            message = L("Dosya okunamadı.", "Couldn't read the file.")
            return
        }
        let n = store.importText(text, source: url.lastPathComponent, key: key, airports: FlightHelpers.airports(state))
        message = n == 0 ? L("Dosyada NOTAM bulunamadı (A1234/26 biçiminde kimlik aranıyor).", "No NOTAMs found (looking for IDs like A1234/26).") : nil
    }
}

extension Notification.Name {
    static let importNotamFile = Notification.Name("importNotamFile")
}

/// Uçuşla ilgili NOTAM'lar: zaman penceresi ve meydan.
enum NotamFilter {
    /// Turun tamamı: kalkıştan 1 sa önce – son inişten 1 sa sonra.
    static func window(_ s: FlightAttributes.ContentState) -> (Date, Date) {
        let start = (s.departureTime ?? s.signOn).addingTimeInterval(-3600)
        let end = (s.lastArrival ?? start.addingTimeInterval(8 * 3600)).addingTimeInterval(3600)
        return (start, max(start, end))
    }

    /// Meydanın uçuşta kullanıldığı saatler: kalkış/iniş ±1 sa; yedekte inişten 3 sa sonrasına kadar; diğerlerinde tur boyu.
    static func windows(_ icao: String, _ s: FlightAttributes.ContentState, alternates: [String]) -> [ClosedRange<Date>] {
        let origin = FlightHelpers.airports(s).first ?? "LTFM"
        let dest = FlightHelpers.destICAO(s)
        var ev: [Date] = []
        if icao == origin, let d = s.departureTime { ev.append(d) }
        if icao == dest {
            if let a = s.turn?.outboundArrival { ev.append(a) }
            if let d = s.turn?.returnDeparture { ev.append(d) }
        }
        if icao == (s.turn?.returnToICAO ?? origin), let a = s.turn?.returnArrival { ev.append(a) }
        for leg in s.extraLegs ?? [] {
            if leg.fromICAO == icao, let d = leg.departure { ev.append(d) }
            if leg.toICAO == icao, let a = leg.arrival { ev.append(a) }
        }
        if !ev.isEmpty { return ev.map { $0.addingTimeInterval(-3600)...$0.addingTimeInterval(3600) } }
        if alternates.contains(icao), let a = s.turn?.outboundArrival ?? s.lastArrival {
            return [a.addingTimeInterval(-1800)...a.addingTimeInterval(3 * 3600)]
        }
        let (a, b) = window(s)
        return [a...b]
    }

    /// Uçuş saatlerinde etkin NOTAM'lar (B–C aralığı ve D programı, meydana göre).
    static func relevant(_ list: [Notam], _ s: FlightAttributes.ContentState, alternates: [String] = []) -> [Notam] {
        list.filter { NotamAnalyzer.isActive($0, in: windows($0.location, s, alternates: alternates)) }
    }
}

/// "Uçuşun için önemli": meydan meydan, kurallarla çıkarılan etkiler.
struct NotamDigest: View {
    let notams: [Notam]
    let state: FlightAttributes.ContentState
    let alternates: [String]
    var perGroup = 5

    var body: some View {
        let origin = FlightHelpers.airports(state).first ?? "LTFM"
        let dest = FlightHelpers.destICAO(state)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(NotamGroup.allCases) { g in
                let items = lines(notams.filter { NotamGroup.of($0, origin: origin, dest: dest, alternates: alternates) == g })
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        let places = Array(Set(items.map(\.location))).sorted()
                        Text(g.title + (g == .enroute ? "" : " · " + places.joined(separator: ", ")))
                            .font(.caption.bold()).foregroundStyle(Palette.secondary)
                        ForEach(items.prefix(perGroup)) { l in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: l.impact.kind.icon).font(.caption).foregroundStyle(l.impact.level.color).frame(width: 18)
                                Text(l.impact.text).font(.subheadline.weight(l.impact.level == .critical ? .bold : .regular))
                                if g == .enroute || places.count > 1 { Text(l.location).font(.caption2.monospaced()).foregroundStyle(Palette.secondary) }
                                Spacer(minLength: 4)
                                if let t = l.time { Text(t).font(.caption2.monospaced()).foregroundStyle(Palette.secondary) }
                            }
                        }
                        if items.count > perGroup {
                            Text(L("+\(items.count - perGroup) daha", "+\(items.count - perGroup) more")).font(.caption2).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
        }
    }

    struct Line: Identifiable { let impact: NotamImpact; let location: String; let time: String?; var id: String { location + impact.id } }

    private func lines(_ list: [Notam]) -> [Line] {
        var seen = Set<String>()
        var out: [Line] = []
        for n in list {
            for i in NotamAnalyzer.impacts(n) where i.level != .info {
                let key = n.location + i.id
                if seen.insert(key).inserted { out.append(Line(impact: i, location: n.location, time: NotamAnalyzer.timeTag(n))) }
            }
        }
        return out.sorted { $0.impact.level < $1.impact.level }
    }
}

struct NotamRow: View {
    let notam: Notam
    var compact = false
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(notam.level.color).frame(width: 8, height: 8)
                Text(notam.location.isEmpty ? notam.id : "\(notam.location) · \(notam.id)")
                    .font(.caption.bold().monospaced()).foregroundStyle(Palette.secondary)
                Spacer()
                if let to = notam.to {
                    Text(L("→ ", "→ ") + FlightHelpers.utc(to) + (notam.toEstimated ? " EST" : ""))
                        .font(.caption2.monospaced()).foregroundStyle(Palette.secondary)
                } else {
                    Text("PERM").font(.caption2.monospaced()).foregroundStyle(Palette.secondary)
                }
            }
            let impacts = NotamAnalyzer.impacts(notam)
            if !impacts.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(impacts) { i in
                        Label(i.text, systemImage: i.kind.icon).font(.subheadline.bold()).foregroundStyle(i.level == .info ? Color.white : i.level.color)
                    }
                    if let t = NotamAnalyzer.timeTag(notam) { Text(t).font(.caption2.monospaced()).foregroundStyle(Palette.secondary) }
                }
            }
            if let s = notam.summary {
                Text(s).font(impacts.isEmpty ? .subheadline.bold() : .footnote)
                Text(L("Yapay zekâ özeti · orijinali kontrol et", "AI summary · check the original"))
                    .font(.caption2).foregroundStyle(Palette.secondary)
            } else {
                Text(NotamDecoder.decode(notam.text)).font(.subheadline).lineLimit(compact ? 3 : nil)
            }
            if !compact {
                Button(showRaw ? L("Orijinali gizle", "Hide original") : L("Orijinal metin", "Original text")) { showRaw.toggle() }
                    .font(.caption.bold())
                if showRaw {
                    Text(notam.raw).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.85)).textSelection(.enabled)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct NotamListView: View {
    let key: String
    let state: FlightAttributes.ContentState
    @ObservedObject var store = NotamStore.shared
    @State private var showInactive = false
    @State private var group: NotamGroup = .departure
    @State private var editingAlts = false
    @State private var altText = ""

    var body: some View {
        let pkg = store.packages[key]
        let all = pkg?.notams ?? []
        let alts = pkg?.alternates ?? []
        let origin = FlightHelpers.airports(state).first ?? "LTFM"
        let dest = FlightHelpers.destICAO(state)
        let relevant = NotamFilter.relevant(all, state, alternates: alts)
        let inGroup: ([Notam]) -> [Notam] = { list in list.filter { NotamGroup.of($0, origin: origin, dest: dest, alternates: alts) == group } }
        let items = inGroup(relevant)
        let inactive = inGroup(all.filter { n in !relevant.contains { $0.id == n.id } })
        List {
            Section {
                Picker("", selection: $group) {
                    ForEach(NotamGroup.allCases) { g in
                        let c = relevant.filter { NotamGroup.of($0, origin: origin, dest: dest, alternates: alts) == g }.count
                        Text(c > 0 ? "\(g.shortTitle) \(c)" : g.shortTitle).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                Text(groupSubtitle(origin: origin, dest: dest, alts: alts)).font(.footnote).foregroundStyle(Palette.secondary)
                if group == .alternate {
                    Button(alts.isEmpty ? L("Yedek meydan ekle", "Add alternates") : L("Yedek meydanları düzenle", "Edit alternates")) {
                        altText = alts.joined(separator: " ")
                        editingAlts = true
                    }
                }
            }
            if !NotamAI.isAvailable {
                Section {
                    Text(L("Bu cihazda Apple Intelligence yok ya da kapalı; NOTAM'lar kısaltmaları açılmış hâlde gösteriliyor.", "Apple Intelligence isn't available on this device; NOTAMs are shown with abbreviations expanded."))
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
            if items.contains(where: { $0.level != .info }) {
                Section(L("Özet", "Summary")) {
                    NotamDigest(notams: items, state: state, alternates: alts, perGroup: 20)
                }
            }
            if items.isEmpty {
                Section { Text(L("Bu grupta uçuş saatinde geçerli NOTAM yok.", "No NOTAMs valid at flight time in this group.")).foregroundStyle(Palette.secondary) }
            }
            ForEach(Notam.Level.allCases, id: \.self) { lv in
                let list = items.filter { $0.level == lv }.sorted { $0.location == $1.location ? $0.id < $1.id : $0.location < $1.location }
                if !list.isEmpty {
                    Section(lv.title + " · \(list.count)") {
                        ForEach(list) { NotamRow(notam: $0) }
                    }
                }
            }
            if !inactive.isEmpty {
                Section {
                    DisclosureGroup(L("Uçuş saatinde geçerli olmayan · \(inactive.count)", "Not valid at flight time · \(inactive.count)"), isExpanded: $showInactive) {
                        ForEach(inactive) { NotamRow(notam: $0) }
                    }
                }
            }
            Section {
                Text(L("Süzme ve sıralama kurallarla yapılır; hiçbir NOTAM silinmez. Resmî kaynak briefing paketinin kendisidir.", "Filtering and sorting are rule-based; no NOTAM is deleted. The briefing pack itself is the official source."))
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("NOTAM")
        .refreshable { await store.summarizeImportant(key) }
        .alert(L("Yedek meydanlar", "Alternates"), isPresented: $editingAlts) {
            TextField("EGSS EGKK", text: $altText).textInputAutocapitalization(.characters)
            Button(L("Kaydet", "Save")) {
                let list = altText.uppercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count == 4 }
                store.setAlternates(key, list)
            }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("ICAO kodlarını boşlukla ayırarak yaz.", "Type ICAO codes separated by spaces."))
        }
    }

    private func groupSubtitle(origin: String, dest: String?, alts: [String]) -> String {
        switch group {
        case .departure: return origin
        case .destination: return dest ?? "—"
        case .alternate: return alts.isEmpty ? L("Briefing'de yedek meydan bulunamadı; elle ekleyebilirsin.", "No alternates found in the briefing; you can add them.") : alts.joined(separator: " · ")
        case .enroute: return L("Diğer meydanlar ve FIR NOTAM'ları", "Other airports and FIR NOTAMs")
        }
    }
}

struct PasteNotamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    let onDone: (String) -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.caption.monospaced())
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(16)
                .background(Palette.bg)
                .navigationTitle(L("NOTAM metni", "NOTAM text"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Vazgeç", "Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Aktar", "Import")) { onDone(text); dismiss() }.bold().disabled(text.isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(L("Panodan yapıştır", "Paste from clipboard")) { text = UIPasteboard.general.string ?? text }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
