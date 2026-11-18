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
        var gifts: [Gift]?
        var questions: [Question]?
        var measurements: [Measurement]?
        var marks: [ScheduleMark]?
        var vitamins: [VitaminMark]?
    }

    /// Silinmemiş kayıtlar, en yeni en üstte.
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var profile = Profile()
    @Published private(set) var nursing: ActiveNursing?

    /// Silinmiş olanlar da dahil ham listeler (eşitleme için). Ekranlar aşağıdaki süzülmüş hâllerini kullanır.
    @Published private(set) var giftsRaw: [Gift] = []
    @Published private(set) var questionsRaw: [Question] = []
    @Published private(set) var measurementsRaw: [Measurement] = []
    @Published private(set) var marksRaw: [ScheduleMark] = []
    @Published private(set) var vitaminsRaw: [VitaminMark] = []
    /// Ailedeki başka bir telefonda devam eden emzirme.
    @Published private(set) var remoteNursing: SharedNursing?

    private var all: [Entry] = []
    private var sharedNursingModified = Date.distantPast
    private let fileURL: URL

    /// Bu telefonun kimliği; kendi emzirme sayacımızı diğerininkinden ayırır.
    static let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }()

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("littlebibi.json")
        if let data = try? Data(contentsOf: fileURL),
           let db = try? JSONDecoder().decode(Database.self, from: data) {
            profile = db.profile
            all = db.entries
            nursing = db.nursing
            giftsRaw = db.gifts ?? []
            questionsRaw = db.questions ?? []
            measurementsRaw = db.measurements ?? []
            marksRaw = db.marks ?? []
            vitaminsRaw = db.vitamins ?? []
        }
        refresh()
        NursingActivity.sync(nursing, babyName: profile.babyName)
        CloudSync.shared.attach(self)
    }

    private func refresh() {
        entries = all.filter { !$0.deleted }.sorted { $0.start > $1.start }
    }

    private func save() {
        let db = Database(profile: profile, entries: all, nursing: nursing, gifts: giftsRaw, questions: questionsRaw,
                          measurements: measurementsRaw, marks: marksRaw, vitamins: vitaminsRaw)
        guard let data = try? JSONEncoder().encode(db) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Profil

    func updateProfile(_ p: Profile) {
        var new = p
        let babyChanged = new.babyName != profile.babyName || new.birthDate != profile.birthDate
        if babyChanged { new.babyModified = Date() }
        profile = new
        save()
        if babyChanged { CloudSync.shared.markDirty(Store.profileRecordName) }
        Reminders.refresh(self)
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
        CloudSync.shared.markDirty(Store.recordName(e.id))
    }

    func delete(_ entry: Entry) {
        guard let i = all.firstIndex(where: { $0.id == entry.id }) else { return }
        all[i].deleted = true
        all[i].modified = Date()
        refresh()
        save()
        CloudSync.shared.markDirty(Store.recordName(entry.id))
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
        sharedNursingModified = Date()
        save()
        NursingActivity.sync(n, babyName: profile.babyName)
        CloudSync.shared.markDirty(Store.nursingRecordName)
    }

    // MARK: Takı, sorular, gelişim, takvim, D vitamini

    var gifts: [Gift] { giftsRaw.filter { !$0.deleted }.sorted { $0.date > $1.date } }
    var questions: [Question] { questionsRaw.filter { !$0.deleted }.sorted { $0.created > $1.created } }
    var measurements: [Measurement] { measurementsRaw.filter { !$0.deleted }.sorted { $0.date > $1.date } }

    private func put<T: SyncRecord>(_ item: T, in list: ReferenceWritableKeyPath<Store, [T]>) {
        var x = item
        x.modified = Date()
        if x.author.isEmpty { x.author = profile.myName }
        if let i = self[keyPath: list].firstIndex(where: { $0.recordName == x.recordName }) {
            self[keyPath: list][i] = x
        } else {
            self[keyPath: list].append(x)
        }
        save()
        CloudSync.shared.markDirty(x.recordName)
    }

    func save(_ gift: Gift) { put(gift, in: \.giftsRaw) }
    func remove(_ gift: Gift) { var g = gift; g.deleted = true; put(g, in: \.giftsRaw) }

    func save(_ question: Question) { put(question, in: \.questionsRaw) }
    func remove(_ question: Question) { var q = question; q.deleted = true; put(q, in: \.questionsRaw) }

    func save(_ measurement: Measurement) { put(measurement, in: \.measurementsRaw) }
    func remove(_ measurement: Measurement) { var m = measurement; m.deleted = true; put(m, in: \.measurementsRaw) }

    func isDone(_ key: String) -> Bool {
        marksRaw.contains { $0.key == key && !$0.deleted && $0.doneAt != nil }
    }

    func setDone(_ key: String, _ done: Bool) {
        var mark = marksRaw.first { $0.key == key } ?? ScheduleMark(key: key)
        mark.deleted = false
        mark.doneAt = done ? Date() : nil
        mark.author = profile.myName
        put(mark, in: \.marksRaw)
        Reminders.refresh(self)
    }

    /// Yapılmamış ve tarihi en yakın takvim maddesi.
    func nextScheduleItem() -> (item: ScheduleItem, due: Date)? {
        guard let birth = profile.birthDate else { return nil }
        return Schedule.items
            .filter { !isDone($0.key) }
            .map { (item: $0, due: $0.due(birth: birth)) }
            .min { $0.due < $1.due }
    }

    func vitaminMark(on date: Date) -> VitaminMark? {
        let key = VitaminMark.dayKey(date)
        return vitaminsRaw.first { $0.day == key && !$0.deleted }
    }

    func setVitamin(given: Bool, on date: Date = Date()) {
        let key = VitaminMark.dayKey(date)
        var mark = vitaminsRaw.first { $0.day == key } ?? VitaminMark(day: key)
        mark.deleted = !given
        mark.givenAt = Date()
        mark.author = profile.myName
        put(mark, in: \.vitaminsRaw)
        Reminders.refresh(self)
    }

    /// Son emzirmeye göre hangi taraftan başlanacağı önerisi:
    /// iki taraf da kullanıldıysa son biten taraf, tek taraf kullanıldıysa diğeri.
    var suggestedSide: Side? {
        guard let last = lastNursing else { return nil }
        if last.leftSeconds > 0 && last.rightSeconds > 0 { return last.lastSide }
        if last.leftSeconds > 0 { return .right }
        if last.rightSeconds > 0 { return .left }
        return nil
    }

    // MARK: Toplu temizlik

    var hasAnyRecords: Bool {
        !entries.isEmpty || !gifts.isEmpty || !questions.isEmpty || !measurements.isEmpty
            || marksRaw.contains { !$0.deleted } || vitaminsRaw.contains { !$0.deleted } || nursing != nil
    }

    /// Deneme kayıtlarını siler. Silinenler "silindi" işaretiyle eşitlenir ki diğer telefondan da kalksın.
    func clearAllRecords() {
        let now = Date()
        var names: [String] = []
        func wipe<T: SyncRecord>(_ list: inout [T]) {
            for i in list.indices where !list[i].deleted {
                list[i].deleted = true
                list[i].modified = now
                names.append(list[i].recordName)
            }
        }
        for i in all.indices where !all[i].deleted {
            all[i].deleted = true
            all[i].modified = now
            names.append(Store.recordName(all[i].id))
        }
        wipe(&giftsRaw)
        wipe(&questionsRaw)
        wipe(&measurementsRaw)
        wipe(&marksRaw)
        wipe(&vitaminsRaw)
        refresh()
        save()
        for name in names { CloudSync.shared.markDirty(name) }
        if nursing != nil { setNursing(nil) }
        Reminders.refresh(self)
    }

    // MARK: Aile eşitlemesi

    static let profileRecordName = "profile"
    static let nursingRecordName = "nursing"
    static func recordName(_ id: UUID) -> String { "e-" + id.uuidString }

    /// Buluta gönderilebilecek her şeyin adı (silinmiş kayıtlar dahil).
    var allRecordNames: [String] {
        var names = all.map { Store.recordName($0.id) }
        names += giftsRaw.map(\.recordName) + questionsRaw.map(\.recordName) + measurementsRaw.map(\.recordName)
        names += marksRaw.map(\.recordName) + vitaminsRaw.map(\.recordName)
        if profile.babyModified != nil { names.append(Store.profileRecordName) }
        return names
    }

    private func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Bir kaydın buluta yazılacak hâli.
    func cloudJSON(for name: String) -> String? {
        if name == Store.profileRecordName {
            guard let modified = profile.babyModified else { return nil }
            return encode(SharedProfile(babyName: profile.babyName, birthDate: profile.birthDate, modified: modified))
        }
        if name == Store.nursingRecordName {
            return encode(SharedNursing(active: nursing, author: profile.myName, device: Store.deviceID, modified: sharedNursingModified))
        }
        switch name.prefix(2) {
        case "e-": return encode(all.first { Store.recordName($0.id) == name })
        case "g-": return encode(giftsRaw.first { $0.recordName == name })
        case "q-": return encode(questionsRaw.first { $0.recordName == name })
        case "m-": return encode(measurementsRaw.first { $0.recordName == name })
        case "s-": return encode(marksRaw.first { $0.recordName == name })
        case "v-": return encode(vitaminsRaw.first { $0.recordName == name })
        default: return nil
        }
    }

    private func merge<T: SyncRecord>(_ data: Data, as type: T.Type, into list: ReferenceWritableKeyPath<Store, [T]>) -> Bool {
        guard let remote = try? JSONDecoder().decode(type, from: data) else { return false }
        if let i = self[keyPath: list].firstIndex(where: { $0.recordName == remote.recordName }) {
            guard remote.modified > self[keyPath: list][i].modified else { return false }
            self[keyPath: list][i] = remote
        } else {
            self[keyPath: list].append(remote)
        }
        return true
    }

    /// Buluttan gelenleri yerel veriyle birleştirir: yeni tarihli olan kazanır.
    /// Bulut sürümünün kazandığı kayıtların adlarını döndürür.
    func applyRemote(_ records: [(name: String, data: Data)]) -> Set<String> {
        var won = Set<String>()
        var entriesChanged = false
        var index: [UUID: Int] = [:]
        for (i, e) in all.enumerated() { index[e.id] = i }
        let decoder = JSONDecoder()

        for record in records {
            let name = record.name
            if name == Store.profileRecordName {
                if let rp = try? decoder.decode(SharedProfile.self, from: record.data),
                   rp.modified > (profile.babyModified ?? .distantPast) {
                    profile.babyName = rp.babyName
                    profile.birthDate = rp.birthDate
                    profile.babyModified = rp.modified
                    won.insert(name)
                }
                continue
            }
            if name == Store.nursingRecordName {
                if let rn = try? decoder.decode(SharedNursing.self, from: record.data), rn.device != Store.deviceID {
                    remoteNursing = rn.active == nil ? nil : rn
                    if rn.modified > sharedNursingModified { won.insert(name) }
                }
                continue
            }
            switch name.prefix(2) {
            case "e-":
                guard let r = try? decoder.decode(Entry.self, from: record.data) else { continue }
                if let i = index[r.id] {
                    if r.modified > all[i].modified {
                        all[i] = r
                        won.insert(name)
                        entriesChanged = true
                    }
                } else {
                    all.append(r)
                    index[r.id] = all.count - 1
                    won.insert(name)
                    entriesChanged = true
                }
            case "g-": if merge(record.data, as: Gift.self, into: \.giftsRaw) { won.insert(name) }
            case "q-": if merge(record.data, as: Question.self, into: \.questionsRaw) { won.insert(name) }
            case "m-": if merge(record.data, as: Measurement.self, into: \.measurementsRaw) { won.insert(name) }
            case "s-": if merge(record.data, as: ScheduleMark.self, into: \.marksRaw) { won.insert(name) }
            case "v-": if merge(record.data, as: VitaminMark.self, into: \.vitaminsRaw) { won.insert(name) }
            default: continue
            }
        }
        if entriesChanged { refresh() }
        if !won.isEmpty {
            save()
            Reminders.refresh(self)
        }
        return won
    }

    /// Paylaşım başlarken, daha önce girilmiş bebek bilgileri de gönderilsin.
    func stampProfileForSharing() {
        guard profile.babyModified == nil, !profile.babyName.isEmpty || profile.birthDate != nil else { return }
        profile.babyModified = Date()
        save()
    }

    /// Başka bir aileye katılırken oradaki bebek bilgileri geçerli olsun.
    func preferRemoteProfile() {
        profile.babyModified = nil
        save()
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
