import CloudKit
import Foundation

/// CloudKit ortak veritabanı (public). Tek kayıt türü: "Entry" (icao, type, payload).
/// Info.plist'te UcusCloudKit = YES değilse hiçbir şey yapmaz (uygulama sadece yerel çalışır).
enum CloudSync {
    static let containerID = "iCloud.com.cengiz.ucus"
    static let recordType = "Entry"

    static var enabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UcusCloudKit") as? String) == "YES"
    }

    private static var db: CKDatabase { CKContainer(identifier: containerID).publicCloudDatabase }

    static func save<T: Encodable & Identifiable>(_ item: T, type: String, icao: String) async where T.ID == UUID {
        guard enabled, let data = try? JSONEncoder().encode(item), let json = String(data: data, encoding: .utf8) else { return }
        let rec = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: item.id.uuidString))
        rec["icao"] = icao as CKRecordValue
        rec["type"] = type as CKRecordValue
        rec["payload"] = json as CKRecordValue
        do { _ = try await db.save(rec) } catch {
            DebugLog.add("CloudKit kayıt hatası: \(error.localizedDescription)")
        }
    }

    static func delete(_ id: UUID) async {
        guard enabled else { return }
        _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: id.uuidString))
    }

    static func fetch(icao: String) async throws -> AirportStore.DataSet {
        var out = AirportStore.DataSet()
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(format: "icao == %@", icao))
        var cursor: CKQueryOperation.Cursor?
        var first = true
        let dec = JSONDecoder()
        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if first {
                page = try await db.records(matching: query, resultsLimit: 400)
                first = false
            } else if let c = cursor {
                page = try await db.records(continuingMatchFrom: c, resultsLimit: 400)
            } else { break }
            for (_, result) in page.matchResults {
                guard case .success(let rec) = result,
                      let type = rec["type"] as? String,
                      let json = rec["payload"] as? String,
                      let data = json.data(using: .utf8) else { continue }
                switch type {
                case "record": if let v = try? dec.decode(FlightRecord.self, from: data) { out.records.append(v) }
                case "note": if let v = try? dec.decode(AirportNote.self, from: data) { out.notes.append(v) }
                case "vote": if let v = try? dec.decode(NoteVote.self, from: data) { out.votes.append(v) }
                case "rating": if let v = try? dec.decode(HotelRating.self, from: data) { out.ratings.append(v) }
                default: break
                }
            }
            cursor = page.queryCursor
        } while cursor != nil && out.records.count + out.notes.count < 4000
        return out
    }
}
