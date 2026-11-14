import ActivityKit
import Foundation
import SwiftUI

/// Uygulamanın tüm verisi. Tek bir JSON dosyasında, cihazda saklanır.
@MainActor
final class Store: ObservableObject {
    private struct Database: Codable {
        var profile: Profile
        var entries: [Entry]
        var nursing: ActiveNursing?
    }

    /// Silinmemiş kayıtlar, en yeni en üstte.
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var profile = Profile()
    @Published private(set) var nursing: ActiveNursing?

    private var all: [Entry] = []
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("littlebibi.json")
        if let data = try? Data(contentsOf: fileURL),
           let db = try? JSONDecoder().decode(Database.self, from: data) {
            profile = db.profile
            all = db.entries
            nursing = db.nursing
        }
        refresh()
        NursingActivity.sync(nursing, babyName: profile.babyName)
    }

    private func refresh() {
        entries = all.filter { !$0.deleted }.sorted { $0.start > $1.start }
    }

    private func save() {
        let db = Database(profile: profile, entries: all, nursing: nursing)
        guard let data = try? JSONEncoder().encode(db) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Profil

    func updateProfile(_ p: Profile) {
        profile = p
        save()
    }

    // MARK: Kayıtlar

    func upsert(_ entry: Entry) {
        var e = entry
        e.modified = Date()
        if e.author.isEmpty { e.author = profile.myName }
        if let i = all.firstIndex(where: { $0.id == e.id }) {
            all[i] = e
        } else {
            all.append(e)
        }
        refresh()
        save()
    }

    func delete(_ entry: Entry) {
        guard let i = all.firstIndex(where: { $0.id == entry.id }) else { return }
        all[i].deleted = true
        all[i].modified = Date()
        refresh()
        save()
    }

    // MARK: Hızlı kayıtlar

    func logBurp() {
        upsert(Entry(kind: .burp, start: Date()))
    }

    var activeSleep: Entry? {
        entries.first { $0.kind == .sleep && $0.end == nil }
    }

    func startSleep() {
        guard activeSleep == nil else { return }
        upsert(Entry(kind: .sleep, start: Date()))
    }

    func endSleep() {
        guard var e = activeSleep else { return }
        e.end = Date()
        upsert(e)
    }

    // MARK: Özetler

    var lastFeed: Entry? { entries.first { $0.isFeed } }
    var lastNursing: Entry? { entries.first { $0.kind == .nursing } }
    var lastDiaper: Entry? { entries.first { $0.kind == .diaper } }
    var lastBottle: Entry? { entries.first { $0.kind == .bottle } }

    func summary(from: Date, to: Date) -> Summary {
        Summary.make(entries, from: from, to: to)
    }

    // MARK: Emzirme sayacı

    /// Bir tarafa dokunuldu: o taraf çalışıyorsa duraklat, değilse o tarafa geç.
    func nursingTap(_ side: Side) {
        let now = Date()
        var n = nursing ?? ActiveNursing(startedAt: now)
        let wasRunningHere = n.isRunning && n.side == side
        n.stopClock(at: now)
        n.side = side
        if !wasRunningHere { n.runningSince = now }
        setNursing(n)
    }

    func nursingPauseResume() {
        guard var n = nursing, n.side != nil else { return }
        let now = Date()
        if n.isRunning {
            n.stopClock(at: now)
        } else {
            n.runningSince = now
        }
        setNursing(n)
    }

    /// Sayacı bitirip kayda çevirir. Bir saniyeden kısa ise kayıt oluşturmaz.
    func finishNursing() {
        guard var n = nursing else { return }
        let now = Date()
        n.stopClock(at: now)
        setNursing(nil)
        guard n.left + n.right >= 1 else { return }
        var e = Entry(kind: .nursing, start: n.startedAt)
        e.id = n.id
        e.end = now
        e.leftSeconds = Int(n.left.rounded())
        e.rightSeconds = Int(n.right.rounded())
        e.lastSide = n.side
        upsert(e)
    }

    func discardNursing() {
        setNursing(nil)
    }

    private func setNursing(_ n: ActiveNursing?) {
        nursing = n
        save()
        NursingActivity.sync(n, babyName: profile.babyName)
    }

    // MARK: Dışa aktarma

    /// Tüm kayıtları Excel'in açabildiği CSV dosyasına yazar.
    func exportCSV() -> URL? {
        var lines = ["tarih;saat;tür;detay;not;giren"]
        for e in entries.reversed() {
            let note = e.kind == .note ? "" : e.note
            let cols = [Fmt.stamp(e.start), e.kind.title, e.detail, note, e.author]
            lines.append(cols.map { $0.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "\n", with: " ") }.joined(separator: ";"))
        }
        let text = "\u{FEFF}" + lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LittleBibi-kayitlar.csv")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// Emzirme sayacını kilit ekranında ve Dynamic Island'da gösterir.
@MainActor
enum NursingActivity {
    static func sync(_ n: ActiveNursing?, babyName: String) {
        Task { @MainActor in
            guard let n, n.side != nil else {
                for a in Activity<NursingAttributes>.activities {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                return
            }
            let state = NursingAttributes.ContentState(
                side: n.side?.rawValue ?? "",
                runningSince: n.runningSince,
                left: n.left,
                right: n.right
            )
            let content = ActivityContent(state: state, staleDate: nil)
            if let current = Activity<NursingAttributes>.activities.first {
                await current.update(content)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                _ = try? Activity.request(
                    attributes: NursingAttributes(babyName: babyName),
                    content: content,
                    pushType: nil
                )
            }
        }
    }
}
