import CloudKit
import Foundation
import SwiftUI
import UIKit

/// Aile eşitlemesi. Kayıtlar, paylaşımı başlatan kişinin iCloud'undaki "Family" bölgesinde durur;
/// davet linkiyle katılan kişi aynı bölgeyi okur ve yazar.
///
/// Her kayıt tek alanlı ("json") bir "Item" kaydıdır. Böylece uygulamaya yeni veri türleri
/// eklendiğinde CloudKit şemasını yeniden yayınlamak gerekmez.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    static let containerID = "iCloud.com.cengiz.bebek"
    static let recordType = "Item"
    static let zoneName = "Family"

    enum Role: String, Codable {
        case none, owner, participant
    }

    struct State: Codable {
        var role: Role = .none
        /// Katılımcı için: bölgenin sahibi.
        var ownerName: String = ""
        var token: Data? = nil
        /// Buluta henüz gönderilmemiş kayıt adları.
        var dirty: Set<String> = []
        var shareURL: String? = nil
        var lastSync: Date? = nil
    }

    private enum SyncError: Error {
        case noAccount
        case badLink
        case ownLink
    }

    @Published private(set) var state = State()
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    private weak var store: Store?
    private lazy var container = CKContainer(identifier: CloudSync.containerID)
    private let defaultsKey = "cloudSyncState"
    private var syncing = false
    private var pending = false
    private var debounce: Task<Void, Never>?
    /// Uygulama davet linkiyle açıldıysa ve veri henüz yüklenmediyse bekleyen davet.
    private var waitingInvite: CKShare.Metadata?

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            state = s
        }
    }

    func attach(_ store: Store) {
        self.store = store
        if let metadata = waitingInvite {
            waitingInvite = nil
            Task { @MainActor in
                await accept(metadata)
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private var database: CKDatabase {
        state.role == .participant ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: CloudSync.zoneName,
            ownerName: state.role == .participant ? state.ownerName : CKCurrentUserDefaultName
        )
    }

    // MARK: Yerel değişiklikler

    func markDirty(_ name: String) {
        guard state.role != .none else { return }
        state.dirty.insert(name)
        persist()
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await sync()
        }
    }

    private func markAllDirty() {
        guard let store else { return }
        state.dirty.formUnion(store.allRecordNames)
    }

    // MARK: Paylaşımı başlat (sahip)

    func startSharing() async {
        guard !busy, let store else { return }
        busy = true
        defer { busy = false }
        do {
            try await ensureAccount()
            let db = container.privateCloudDatabase
            let zid = CKRecordZone.ID(zoneName: CloudSync.zoneName, ownerName: CKCurrentUserDefaultName)
            _ = try await db.save(CKRecordZone(zoneID: zid))

            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zid)
            var share: CKShare
            do {
                if let existing = try await db.record(for: shareID) as? CKShare {
                    share = existing
                } else {
                    share = CKShare(recordZoneID: zid)
                }
            } catch {
                share = CKShare(recordZoneID: zid)
            }
            share[CKShare.SystemFieldKey.title] = "LittleBibi" as CKRecordValue
            // Linki alan herkes katılabilir; linki yalnızca aileyle paylaşın.
            share.publicPermission = .readWrite
            let saved = try await db.save(share)
            let url = (saved as? CKShare)?.url ?? share.url

            if state.role != .owner {
                state.role = .owner
                state.ownerName = ""
                state.token = nil
            }
            state.shareURL = url?.absoluteString
            store.stampProfileForSharing()
            markAllDirty()
            persist()
            message = nil
            await sync()
        } catch {
            report(error)
        }
    }

    /// Davet linkini geçersiz kılar. Kayıtlar kendi iCloud'unuzda durmaya devam eder.
    func stopSharing() async {
        guard !busy, state.role == .owner else { return }
        busy = true
        defer { busy = false }
        do {
            let zid = CKRecordZone.ID(zoneName: CloudSync.zoneName, ownerName: CKCurrentUserDefaultName)
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zid)
            _ = try await container.privateCloudDatabase.deleteRecord(withID: shareID)
            state.shareURL = nil
            persist()
            message = "Paylaşım durduruldu. Eski davet linki artık çalışmaz."
        } catch let e as CKError where e.code == .unknownItem {
            state.shareURL = nil
            persist()
        } catch {
            report(error)
        }
    }

    // MARK: Katıl (katılımcı)

    /// Yapıştırılan davet linkiyle katılır.
    func join(link: String) async {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            report(SyncError.badLink)
            return
        }
        busy = true
        do {
            try await ensureAccount()
            let metadata = try await container.shareMetadata(for: url)
            busy = false
            await accept(metadata)
        } catch {
            busy = false
            report(error)
        }
    }

    /// Davet linkine dokunulduğunda sistemin verdiği bilgiyle katılır.
    func accept(_ metadata: CKShare.Metadata) async {
        guard let store else {
            waitingInvite = metadata
            return
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if metadata.participantRole == .owner {
                throw SyncError.ownLink
            }
            if metadata.participantStatus != .accepted {
                _ = try await container.accept(metadata)
            }
            let zid = metadata.share.recordID.zoneID
            state.role = .participant
            state.ownerName = zid.ownerName
            state.token = nil
            state.shareURL = nil
            state.dirty = []
            store.preferRemoteProfile()
            markAllDirty()
            persist()
            message = nil
            await sync()
        } catch {
            report(error)
        }
    }

    /// Aileden ayrılır. Telefondaki kayıtlar silinmez.
    func leave() async {
        guard !busy, state.role == .participant else { return }
        busy = true
        defer { busy = false }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        _ = try? await container.sharedCloudDatabase.deleteRecord(withID: shareID)
        state = State()
        persist()
        message = "Aileden ayrıldınız. Kayıtlar bu telefonda duruyor."
    }

    // MARK: Eşitleme

    func sync() async {
        guard state.role != .none, let store else { return }
        if syncing {
            pending = true
            return
        }
        syncing = true
        defer { syncing = false }
        repeat {
            pending = false
            do {
                try await pull(store)
                try await push(store)
                state.lastSync = Date()
                persist()
                message = nil
            } catch {
                persist()
                report(error)
                return
            }
        } while pending
    }

    private func pull(_ store: Store) async throws {
        var more = true
        var retried = false
        while more {
            let token = state.token.flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
            }
            do {
                let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                var entries: [Entry] = []
                var profile: SharedProfile?
                let decoder = JSONDecoder()
                for (id, item) in result.modificationResultsByID {
                    guard case .success(let modification) = item else { continue }
                    let record = modification.record
                    guard record.recordType == CloudSync.recordType,
                          let json = record["json"] as? String,
                          let data = json.data(using: .utf8) else { continue }
                    if id.recordName == Store.profileRecordName {
                        profile = try? decoder.decode(SharedProfile.self, from: data)
                    } else if let entry = try? decoder.decode(Entry.self, from: data) {
                        entries.append(entry)
                    }
                }
                let won = store.applyRemote(entries: entries, profile: profile)
                state.dirty.subtract(won)
                state.token = try? NSKeyedArchiver.archivedData(withRootObject: result.changeToken, requiringSecureCoding: true)
                more = result.moreComing
            } catch let e as CKError where e.code == .changeTokenExpired && !retried {
                retried = true
                state.token = nil
            }
        }
    }

    private func push(_ store: Store) async throws {
        let names = Array(state.dirty)
        guard !names.isEmpty else { return }
        var failure: Error?
        var start = 0
        while start < names.count {
            let chunk = names[start..<min(start + 200, names.count)]
            start += 200
            var sent: [String: String] = [:]
            var records: [CKRecord] = []
            for name in chunk {
                guard let json = store.cloudJSON(for: name) else {
                    state.dirty.remove(name)
                    continue
                }
                let record = CKRecord(recordType: CloudSync.recordType, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
                record["json"] = json as CKRecordValue
                records.append(record)
                sent[name] = json
            }
            if records.isEmpty { continue }
            let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            for (id, item) in result.saveResults {
                switch item {
                case .success:
                    // Gönderim sırasında yeniden değiştiyse bir sonraki turda tekrar gönderilir.
                    if store.cloudJSON(for: id.recordName) == sent[id.recordName] {
                        state.dirty.remove(id.recordName)
                    }
                case .failure(let error):
                    failure = error
                }
            }
            persist()
        }
        if let failure { throw failure }
    }

    private func ensureAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw SyncError.noAccount }
    }

    // MARK: Hatalar

    private func report(_ error: Error) {
        if let e = error as? SyncError {
            switch e {
            case .noAccount:
                message = "Bu telefonda iCloud'a giriş yapılmamış ya da iCloud Drive kapalı. Ayarlar'dan iCloud'u açıp tekrar deneyin."
            case .badLink:
                message = "Bu bir davet linkine benzemiyor. Linkin tamamını yapıştırın."
            case .ownLink:
                message = "Bu sizin kendi davet linkiniz. Linki eşinize gönderin."
            }
            return
        }
        guard let ck = error as? CKError else {
            message = "Eşitlenemedi: \(error.localizedDescription)"
            return
        }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            message = "Şu an iCloud'a ulaşılamıyor. Bağlantı gelince kendiliğinden eşitlenecek."
        case .notAuthenticated:
            message = "Bu telefonda iCloud'a giriş yapılmamış. Ayarlar'dan iCloud'u açıp tekrar deneyin."
        case .quotaExceeded:
            message = "iCloud saklama alanı dolu. Yer açılınca eşitleme devam eder."
        case .zoneNotFound, .userDeletedZone:
            if state.role == .participant {
                state = State()
                persist()
                message = "Paylaşım sonlandırılmış. Kayıtlar bu telefonda duruyor; yeniden katılmak için yeni bir davet linki gerekir."
            } else {
                state.token = nil
                persist()
                message = "iCloud'daki aile alanı bulunamadı. \"Eşimle paylaş\" ile yeniden oluşturabilirsiniz."
            }
        case .unknownItem:
            message = "iCloud veri yapısı henüz yayına alınmamış görünüyor (Item kaydı bulunamadı)."
        case .partialFailure:
            let inner = ck.partialErrorsByItemID?.values.first
            if let inner, (inner as? CKError)?.code != .partialFailure {
                report(inner)
            } else {
                message = "Bazı kayıtlar eşitlenemedi: \(ck.localizedDescription)"
            }
        default:
            message = "Eşitlenemedi (\(ck.code.rawValue)): \(ck.localizedDescription)"
        }
    }
}

// MARK: Davet linkine dokunulduğunda

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in
                await CloudSync.shared.accept(metadata)
            }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            await CloudSync.shared.accept(cloudKitShareMetadata)
        }
    }
}
