import SwiftUI
import UniformTypeIdentifiers

/// Drill kodu tablosundaki bir satır. İçeriği kullanıcı girer (şirket OM'sinden); uygulama telifli tablo içermez.
struct DrillEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var code: String        // "3" ya da harf: "L"
    var title: String       // kısa başlık
    var actions: String     // yapılacaklar
}

/// Bu uçuştaki tehlikeli madde (NOTOC'tan).
struct DGItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var drill: String = ""       // "3L"
    var un: String = ""          // "UN1263"
    var position: String = ""    // "31L kargo"
}

@MainActor
final class DrillStore: ObservableObject {
    static let shared = DrillStore()
    private let key = "drillTable"
    @Published private(set) var entries: [DrillEntry] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let e = try? JSONDecoder().decode([DrillEntry].self, from: d) {
            entries = e
        }
    }

    func save(_ e: DrillEntry) {
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
        persist()
    }
    func delete(_ e: DrillEntry) { entries.removeAll { $0.id == e.id }; persist() }

    /// "kod;başlık;yapılacaklar" satırları (CSV/TXT). Aynı kodlu satırların yerine geçer. Eklenen satır sayısı.
    func importLines(_ text: String) -> Int {
        var n = 0
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, !parts[0].isEmpty, parts[0].count <= 3 else { continue }
            let e = DrillEntry(code: parts[0].uppercased(), title: parts[1], actions: parts.count > 2 ? parts[2].replacingOccurrences(of: "\\n", with: "\n") : "")
            entries.removeAll { $0.code == e.code }
            entries.append(e)
            n += 1
        }
        persist()
        return n
    }

    /// "3L" → [3 numaralı satır, L harfi satırı]
    func lookup(_ drill: String) -> [DrillEntry] {
        let d = drill.uppercased().filter { !$0.isWhitespace }
        let digits = String(d.prefix { $0.isNumber })
        let letters = d.dropFirst(digits.count).map(String.init)
        var out: [DrillEntry] = []
        if !digits.isEmpty, let e = entries.first(where: { $0.code == digits }) { out.append(e) }
        for l in letters { if let e = entries.first(where: { $0.code == l }) { out.append(e) } }
        return out
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(d, forKey: key) }
    }

    var sorted: [DrillEntry] {
        entries.sorted { a, b in
            let ia = Int(a.code), ib = Int(b.code)
            switch (ia, ib) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.code < b.code
            }
        }
    }
}

/// Drill kodu tablosu: arama, düzenleme, içe aktarma.
struct DrillTableView: View {
    @ObservedObject var store = DrillStore.shared
    @State private var search = ""
    @State private var editing: DrillEntry?
    @State private var importing = false
    @State private var note: String?

    var body: some View {
        List {
            let q = search.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let hits = store.lookup(q)
                Section(L("\"\(q.uppercased())\" için", "For \"\(q.uppercased())\"")) {
                    if hits.isEmpty {
                        Text(L("Tabloda bu kod yok.", "This code isn't in your table.")).foregroundStyle(Palette.secondary)
                    }
                    ForEach(hits) { DrillRow(entry: $0, expanded: true) }
                }
            }
            if store.entries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Tablo boş", "The table is empty")).font(.headline)
                        Text(L("Drill kodu tablosu ICAO'nun telifli yayınında (Doc 9481) yer alır, bu yüzden uygulamada hazır gelmez. Şirketinin OM'sindeki tabloyu buraya gir ya da \"kod;başlık;yapılacaklar\" satırlarından oluşan bir dosyayı içe aktar.",
                               "The drill code table is part of ICAO's copyrighted Doc 9481, so it isn't bundled. Enter your company OM's table here, or import a file of \"code;title;actions\" lines."))
                            .font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                }
            } else {
                Section(L("Tablo", "Table")) {
                    ForEach(store.sorted) { e in
                        Button { editing = e } label: { DrillRow(entry: e, expanded: false) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { idx in idx.map { store.sorted[$0] }.forEach(store.delete) }
                }
            }
            if let note { Section { Text(note).font(.footnote) } }
            Section {
                Text(L("Resmî kaynak şirket OM'si ve ICAO Doc 9481'dir.", "The official sources are your company OM and ICAO Doc 9481."))
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .searchable(text: $search, prompt: L("Drill kodu (örn. 3L)", "Drill code (e.g. 3L)"))
        .navigationTitle(L("DG drill kodları", "DG drill codes"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = DrillEntry(code: "", title: "", actions: "") } label: { Label(L("Satır ekle", "Add row"), systemImage: "plus") }
                    Button { importing = true } label: { Label(L("Dosyadan içe aktar", "Import from file"), systemImage: "square.and.arrow.down") }
                } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel(L("Ekle", "Add"))
            }
        }
        .sheet(item: $editing) { DrillEditor(entry: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .commaSeparatedText, .text]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let n = store.importLines(text)
                note = L("\(n) satır içe aktarıldı.", "\(n) rows imported.")
            } else {
                note = L("Dosya okunamadı.", "Couldn't read the file.")
            }
        }
    }
}

struct DrillRow: View {
    let entry: DrillEntry
    var expanded: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.code).font(.title3.bold().monospaced()).foregroundStyle(Palette.warn).frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.subheadline.bold())
                if !entry.actions.isEmpty {
                    Text(entry.actions).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(expanded ? nil : 2)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct DrillEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: DrillEntry

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Kod", "Code")) {
                    TextField(L("1–11 ya da harf (A, L, M …)", "1–11 or a letter (A, L, M …)"), text: $entry.code)
                        .textInputAutocapitalization(.characters)
                }
                Section(L("Başlık", "Title")) { TextField(L("Kısa açıklama", "Short description"), text: $entry.title) }
                Section(L("Yapılacaklar", "Actions")) {
                    TextField(L("OM'deki adımlar", "Steps from the OM"), text: $entry.actions, axis: .vertical).lineLimit(3...12)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle(L("Drill kodu", "Drill code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Vazgeç", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Kaydet", "Save")) {
                        entry.code = entry.code.uppercased().trimmingCharacters(in: .whitespaces)
                        DrillStore.shared.save(entry)
                        dismiss()
                    }
                    .bold()
                    .disabled(entry.code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Brifing'deki "Uçakta DG" kartı.
struct DGCard: View {
    let key: String
    @ObservedObject var briefing = BriefingStore.shared
    @ObservedObject var drills = DrillStore.shared
    @State private var editing: DGItem?

    var body: some View {
        let items = briefing.notes(key).dgItems ?? []
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("Uçakta DG", "Dangerous goods")).font(.headline)
                    Spacer()
                    NavigationLink { DrillTableView() } label: {
                        Text(L("Drill tablosu", "Drill table")).font(.caption.bold())
                    }
                }
                if items.isEmpty {
                    Text(L("NOTOC'taki drill kodunu ekle; tablondaki yapılacaklar hemen açılır.", "Add the drill code from the NOTOC; the actions from your table open right away."))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
                ForEach(items) { item in
                    Button { editing = item } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(item.drill.isEmpty ? "—" : item.drill).font(.title3.bold().monospaced()).foregroundStyle(Palette.warn)
                                Text([item.un, item.position].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                                Spacer()
                            }
                            ForEach(drills.lookup(item.drill)) { DrillRow(entry: $0, expanded: true) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { editing = DGItem() } label: {
                    Label(L("DG ekle", "Add DG"), systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(item: $editing) { item in
            DGEditor(item: item, isNew: !(briefing.notes(key).dgItems ?? []).contains { $0.id == item.id }) { result in
                briefing.update(key) { n in
                    var list = n.dgItems ?? []
                    if let result {
                        if let i = list.firstIndex(where: { $0.id == result.id }) { list[i] = result } else { list.append(result) }
                    } else {
                        list.removeAll { $0.id == item.id }
                    }
                    n.dgItems = list.isEmpty ? nil : list
                }
            }
        }
    }
}

struct DGEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: DGItem
    let isNew: Bool
    let onDone: (DGItem?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Drill kodu", "Drill code")) {
                    TextField("3L", text: $item.drill).textInputAutocapitalization(.characters)
                }
                Section(L("UN numarası", "UN number")) { TextField("UN1263", text: $item.un).textInputAutocapitalization(.characters) }
                Section(L("Konum", "Position")) { TextField(L("Örn. 31L, arka kargo", "e.g. 31L, aft hold"), text: $item.position) }
                if !isNew {
                    Section { Button(L("Sil", "Delete"), role: .destructive) { onDone(nil); dismiss() } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle(L("Uçakta DG", "Dangerous goods"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Vazgeç", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Kaydet", "Save")) { onDone(item); dismiss() }.bold()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
