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
        let relevant = pkg.map { NotamFilter.relevant($0.notams, state) } ?? []
        let critical = relevant.filter { $0.level == .critical }
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
                    ForEach(critical.prefix(4)) { NotamRow(notam: $0, compact: true) }
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
                let n = store.importText(text, source: L("Yapıştırılan metin", "Pasted text"), key: key)
                message = n == 0 ? L("Metinde NOTAM bulunamadı.", "No NOTAMs found in the text.") : nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importNotamFile)) { note in
            if let url = note.object as? URL { load(url) }
        }
    }

    private func load(_ url: URL) {
        guard let text = NotamParser.pdfText(url), !text.isEmpty else {
            message = L("Dosya okunamadı.", "Couldn't read the file.")
            return
        }
        let n = store.importText(text, source: url.lastPathComponent, key: key)
        message = n == 0 ? L("Dosyada NOTAM bulunamadı (A1234/26 biçiminde kimlik aranıyor).", "No NOTAMs found (looking for IDs like A1234/26).") : nil
    }
}

extension Notification.Name {
    static let importNotamFile = Notification.Name("importNotamFile")
}

/// Uçuşla ilgili NOTAM'lar: zaman penceresi ve meydan.
enum NotamFilter {
    /// Uçuş penceresi: kalkıştan 1 sa önce – (dönüş) inişten 1 sa sonra.
    static func window(_ s: FlightAttributes.ContentState) -> (Date, Date) {
        let start = (s.departureTime ?? s.signOn).addingTimeInterval(-3600)
        let end = (s.turn?.returnArrival ?? s.turn?.outboundArrival ?? start.addingTimeInterval(8 * 3600)).addingTimeInterval(3600)
        return (start, end)
    }

    static func relevant(_ list: [Notam], _ s: FlightAttributes.ContentState) -> [Notam] {
        let (a, b) = window(s)
        return list.filter { NotamClassifier.isActive($0, from: a, to: b) }
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
            if let s = notam.summary {
                Text(s).font(.subheadline.bold())
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

    var body: some View {
        let all = store.packages[key]?.notams ?? []
        let relevant = NotamFilter.relevant(all, state)
        let inactive = all.filter { n in !relevant.contains { $0.id == n.id } }
        let airports = FlightHelpers.airports(state)
        List {
            if !NotamAI.isAvailable {
                Section {
                    Text(L("Bu cihazda Apple Intelligence yok ya da kapalı; NOTAM'lar kısaltmaları açılmış hâlde gösteriliyor.", "Apple Intelligence isn't available on this device; NOTAMs are shown with abbreviations expanded."))
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
            ForEach(Notam.Level.allCases, id: \.self) { lv in
                let items = relevant.filter { $0.level == lv }.sorted { a, b in
                    let ia = airports.firstIndex(of: a.location) ?? 99, ib = airports.firstIndex(of: b.location) ?? 99
                    return ia == ib ? a.id < b.id : ia < ib
                }
                if !items.isEmpty {
                    Section(lv.title + " · \(items.count)") {
                        ForEach(items) { NotamRow(notam: $0) }
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
